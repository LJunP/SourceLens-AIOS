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

    FALSE_EFFECTS = {
      "network" => false,
      "provider" => false,
      "secret" => false,
      "remote" => false,
      "production" => false,
      "public" => false
    }.freeze
    LOCAL_GATEWAY_EFFECTS = {
      "network" => true,
      "provider" => true,
      "secret" => true,
      "remote" => false,
      "production" => false,
      "public" => false
    }.freeze

    def effect_map!(value, label, expected = FALSE_EFFECTS)
      effects = mapping!(value, label)
      keys = %w[network provider secret remote production public]
      stop!("#{label} keys drifted") unless effects.keys.sort == keys.sort
      stop!("#{label} does not equal the exact authorized effect map") unless effects == expected
      effects
    end

    def exact_keys!(value, expected, label)
      record = mapping!(value, label)
      stop!("#{label} keys drifted") unless record.keys.sort == expected.sort
      record
    end

    def founder_profile!(value, route_id, task_id, label)
      profile = exact_keys!(
        value,
        %w[schema_version profile_id decision_basis route_id task_id transport model secret call_limits request_limits egress external_effects claim_limits],
        label
      )
      stop!("#{label} schema drift") unless profile["schema_version"] == "1.0"
      stop!("#{label} route drift") unless profile["route_id"] == route_id
      stop!("#{label} Task drift") unless profile["task_id"] == task_id
      nonempty_string!(profile["decision_basis"], "#{label}.decision_basis")

      transport = exact_keys!(
        profile["transport"],
        %w[scheme host port base_path metadata_path completion_path api_format method follow_redirects use_proxy dns_resolution fallback_endpoint_allowed expected_peer_address expected_peer_port],
        "#{label}.transport"
      )
      expected_transport = {
        "scheme" => "http",
        "host" => "127.0.0.1",
        "port" => 8787,
        "base_path" => "/v1",
        "metadata_path" => "/v1/models",
        "completion_path" => "/v1/chat/completions",
        "api_format" => "OPENAI_COMPATIBLE_CHAT_COMPLETIONS",
        "method" => "POST",
        "follow_redirects" => false,
        "use_proxy" => false,
        "dns_resolution" => false,
        "fallback_endpoint_allowed" => false,
        "expected_peer_address" => "127.0.0.1",
        "expected_peer_port" => 8787
      }
      stop!("#{label} transport exceeds literal loopback boundary") unless transport == expected_transport

      model = exact_keys!(profile["model"], %w[requested_model substitution_allowed provider_provenance],
                          "#{label}.model")
      nonempty_string!(model["requested_model"], "#{label}.model.requested_model")
      stop!("#{label} allows model substitution") unless model["substitution_allowed"] == false
      stop!("#{label} overclaims provider provenance") unless
        model["provider_provenance"] == "OPENAI_FOUNDER_ATTESTED_GATEWAY_NOT_INDEPENDENTLY_VERIFIED"

      secret = exact_keys!(profile["secret"], %w[env_name source persist log_hash_or_evidence_allowed],
                           "#{label}.secret")
      stop!("#{label} secret env invalid") unless
        secret["env_name"].is_a?(String) && secret["env_name"].match?(/\A[A-Z][A-Z0-9_]*\z/)
      stop!("#{label} secret source drift") unless secret["source"] == "FOUNDER_TRANSIENT_UI_INPUT"
      stop!("#{label} permits secret persistence") unless
        secret["persist"] == false && secret["log_hash_or_evidence_allowed"] == false

      calls = exact_keys!(
        profile["call_limits"],
        %w[metadata_max metadata_used_before_activation source_bearing_max source_bearing_used_before_activation automatic_retry_max ambiguous_send_retry_allowed],
        "#{label}.call_limits"
      )
      stop!("#{label} call limits drift") unless calls == {
        "metadata_max" => 1,
        "metadata_used_before_activation" => 1,
        "source_bearing_max" => 1,
        "source_bearing_used_before_activation" => 0,
        "automatic_retry_max" => 0,
        "ambiguous_send_retry_allowed" => false
      }

      limits = exact_keys!(profile["request_limits"],
                           %w[max_input_tokens max_output_tokens timeout_seconds request_body_max_bytes response_body_max_bytes],
                           "#{label}.request_limits")
      caps = {
        "max_input_tokens" => 4096,
        "max_output_tokens" => 1024,
        "timeout_seconds" => 120,
        "request_body_max_bytes" => 32768,
        "response_body_max_bytes" => 131072
      }
      caps.each do |key, cap|
        positive_integer!(limits[key], "#{label}.request_limits.#{key}")
        stop!("#{label}.request_limits.#{key} exceeds cap") unless limits[key] <= cap
      end

      egress = exact_keys!(profile["egress"], %w[allowed_artifact_ids forbidden_categories], "#{label}.egress")
      stop!("#{label} egress allowlist drift") unless egress["allowed_artifact_ids"] == %w[
        P1_035_REP001_ISSUE_TEXT
        P1_035_REP001_ALLOWED_CLARIFICATIONS
        P1_035_REP001_ACCEPTED_BASELINE_CONTEXT
        P1_062_FINITE_IR_RESPONSE_INSTRUCTION
      ]
      stop!("#{label} egress denylist drift") unless egress["forbidden_categories"] == %w[
        SOURCE_BYTES TEST_BYTES REFERENCE_PATCH EVALUATOR_BYTES GOVERNANCE_OR_TRUTH_BYTES
        SECRET_OR_AUTHORIZATION_HEADER HIDDEN_TASK_OR_HIDDEN_EVIDENCE
      ]
      effect_map!(profile["external_effects"], "#{label}.external_effects", LOCAL_GATEWAY_EFFECTS)
      claims = exact_keys!(profile["claim_limits"],
                           %w[direct_openai_provenance_proven upstream_provider upstream_request_count monetary_cost],
                           "#{label}.claim_limits")
      stop!("#{label} claim boundary drift") unless claims == {
        "direct_openai_provenance_proven" => false,
        "upstream_provider" => "OPENAI_FOUNDER_ATTESTED",
        "upstream_request_count" => "UNKNOWN",
        "monetary_cost" => "UNKNOWN_USER_MANAGED_GATEWAY"
      }
      profile
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
      "max_same_task_repairs" => 1
    }
    single_resource_limits.each do |key, expected|
      stop!("P1 route envelope #{key} drift") unless envelope[key] == expected
    end
    contract_corrections = envelope["max_contract_corrections_per_task"]
    stop!("P1 route contract-correction limit must be zero or one") unless
      contract_corrections.is_a?(Integer) && contract_corrections.between?(0, 1)
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
    route_profile = if route.key?("founder_reserved_profile") && !route["founder_reserved_profile"].nil?
                      founder_profile!(route["founder_reserved_profile"], route["route_id"], first_task_id,
                                       "current_phase_route.founder_reserved_profile")
                    end
    authorized_effects = route_profile ? route_profile["external_effects"] : FALSE_EFFECTS
    effect_map!(envelope["external_effects"], "current_phase_route.envelope.external_effects",
                authorized_effects)
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
    current_task = active["current_task"]
    goal_task = truth.dig("goal", "current_task_authority")

    if current_task == "NONE"
      effect_map!(active["external_effects"], "active_work.external_effects")
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
      contract = validate_bound_contract!(repo_root, contract_binding, current_task)
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
      effect_map!(active["external_effects"], "active_work.external_effects", authorized_effects)
      effect_map!(contract["external_effects"], "active Task Contract external_effects",
                  authorized_effects)
      if route_profile
        contract_profile = founder_profile!(contract["founder_reserved_profile"], route["route_id"], current_task,
                                            "active Task Contract founder_reserved_profile")
        stop!("active Task Contract profile mismatch") unless contract_profile == route_profile
      else
        stop!("offline active Task Contract invented a Founder-reserved provider profile") unless
          !contract.key?("founder_reserved_profile") || contract["founder_reserved_profile"].nil?
      end
      packet = decision_packet
      stop!("active Founder authorization path drift") unless
        active["founder_reserved_authorization"] == packet["path"]
      stop!("active Founder authorization SHA drift") unless
        active["founder_reserved_authorization_sha256"] == packet["sha256"]
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

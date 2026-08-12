#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRUTH_PATH="${ROOT_DIR}/docs/aios/truth/project_state.yaml"
RULES_PATH="${ROOT_DIR}/AGENTS.md"

fail() {
  echo "AIOS GOVERNANCE FAIL: $*" >&2
  exit 1
}

check_founder_knowledge_section() {
  local rules_path="$1"
  local section_header='## Founder Knowledge System（常驻规则）'
  local canonical_byte_length='3039'
  local canonical_sha256='0dc016ebadc02abd32c7852c86ce30b956df302cf18cb2f37d532018da131998'

  ruby -rdigest -e '
    rules_path, header, expected_length, expected_sha = ARGV
    header = header.dup.force_encoding("UTF-8")
    abort "Founder Knowledge System rules file missing" unless File.file?(rules_path) && !File.symlink?(rules_path)
    bytes = File.binread(rules_path)
    rules = bytes.dup.force_encoding("UTF-8")
    abort "Founder Knowledge System document encoding invalid" unless rules.valid_encoding?
    lines = rules.lines
    starts = lines.each_index.select { |index| lines[index].sub(/\r?\n\z/, "") == header }
    abort "Founder Knowledge System exact section missing or duplicated" unless starts.length == 1
    start_index = starts.first
    end_index = ((start_index + 1)...lines.length).find { |index| lines[index].start_with?("## ") }
    abort "Founder Knowledge System must be the terminal H2 section" if end_index
    section = lines[start_index...lines.length].join
    canonical = section.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    abort "Founder Knowledge System exact section byte drift" unless
      canonical.bytesize == Integer(expected_length, 10) && Digest::SHA256.hexdigest(canonical) == expected_sha
  ' "$rules_path" "$section_header" "$canonical_byte_length" "$canonical_sha256" \
    || fail "Founder Knowledge System exact section drift"
}

check_phase_sequence_section() {
  local rules_path="$1"
  local section_header='## 严格阶段顺序与反偏航（强制执行）'
  local canonical_byte_length='2304'
  local canonical_sha256='978f0bfa2ae792da579e7ebd6c2a5cf693d7e9ccb92be807267b86a912635038'

  ruby -rdigest -e '
    rules_path, header, expected_length, expected_sha = ARGV
    header = header.dup.force_encoding("UTF-8")
    abort "phase sequence rules file missing" unless File.file?(rules_path) && !File.symlink?(rules_path)
    bytes = File.binread(rules_path)
    rules = bytes.dup.force_encoding("UTF-8")
    abort "phase sequence rules document encoding invalid" unless rules.valid_encoding?
    lines = rules.lines
    starts = lines.each_index.select { |index| lines[index].sub(/\r?\n\z/, "") == header }
    abort "phase sequence exact section missing or duplicated" unless starts.length == 1
    start_index = starts.first
    end_index = ((start_index + 1)...lines.length).find { |index| lines[index].start_with?("## ") }
    abort "phase sequence section must be followed by another H2 section" unless end_index
    section = lines[start_index...end_index].join
    canonical = section.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    abort "phase sequence exact section byte drift" unless
      canonical.bytesize == Integer(expected_length, 10) && Digest::SHA256.hexdigest(canonical) == expected_sha
  ' "$rules_path" "$section_header" "$canonical_byte_length" "$canonical_sha256" \
    || fail "strict phase sequence exact section drift"
}

check_founder_action_handoff_section() {
  local rules_path="$1"
  local section_header='## Founder / 用户下一步交付（强制执行）'
  local canonical_byte_length='3519'
  local canonical_sha256='63c9f93e4fd1f9ea3c2bd6cf9fa8fe6a11f54068b8e5b70097a96fb9bddfa709'

  ruby -rdigest -e '
    rules_path, header, expected_length, expected_sha = ARGV
    header = header.dup.force_encoding("UTF-8")
    abort "Founder action handoff rules file missing" unless File.file?(rules_path) && !File.symlink?(rules_path)
    rules = File.binread(rules_path).dup.force_encoding("UTF-8")
    abort "Founder action handoff document encoding invalid" unless rules.valid_encoding?
    lines = rules.lines
    starts = lines.each_index.select { |index| lines[index].sub(/\r?\n\z/, "") == header }
    abort "Founder action handoff exact section missing or duplicated" unless starts.length == 1
    start_index = starts.first
    end_index = ((start_index + 1)...lines.length).find { |index| lines[index].start_with?("## ") }
    abort "Founder action handoff section must be followed by another H2 section" unless end_index
    section = lines[start_index...end_index].join
    canonical = section.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    abort "Founder action handoff exact section byte drift" unless
      canonical.bytesize == Integer(expected_length, 10) && Digest::SHA256.hexdigest(canonical) == expected_sha
  ' "$rules_path" "$section_header" "$canonical_byte_length" "$canonical_sha256" \
    || fail "Founder action handoff exact section drift"
}

check_authority_bindings() {
  ruby -ryaml -rdigest -rpathname -e '
    repo_root = Pathname.new(ARGV.fetch(0)).realpath
    truth_path = Pathname.new(ARGV.fetch(1))
    abort "Truth missing or symlinked" unless truth_path.file? && !truth_path.symlink?
    truth = YAML.safe_load(truth_path.read, permitted_classes: [], permitted_symbols: [], aliases: false)
    abort "Truth must be a mapping" unless truth.is_a?(Hash)
    authority = truth["authority"]
    abort "authority mapping missing" unless authority.is_a?(Hash)

    expected = {
      "strategy" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "execution_protocol" => "docs/aios/MASTER_EXECUTION_PROTOCOL.md",
      "founder_delegation_policy" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "evaluation_protocol" => "docs/aios/EVALUATION_PROTOCOL.md"
    }
    expected.each do |key, expected_path|
      binding = authority[key]
      abort "#{key} authority binding missing" unless binding.is_a?(Hash)
      path = binding["path"]
      digest = binding["sha256"]
      abort "#{key} authority path drift" unless path == expected_path
      abort "#{key} authority SHA-256 invalid" unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      relative = Pathname.new(path)
      abort "#{key} authority path must be repository-relative" if relative.absolute? || relative.each_filename.any? { |part| part == ".." }
      candidate = repo_root.join(relative).cleanpath
      abort "#{key} authority file missing or symlinked" unless candidate.file? && !candidate.symlink?
      real_candidate = candidate.realpath
      prefix = repo_root.to_s + File::SEPARATOR
      abort "#{key} authority path escaped repository" unless real_candidate.to_s.start_with?(prefix)
      abort "#{key} authority hash drift" unless Digest::SHA256.file(real_candidate).hexdigest == digest
      abort "#{key} authority status missing" unless binding["status"].is_a?(String) && !binding["status"].empty?
    end

    abort "Truth current_facts path drift" unless authority["current_facts"] == "docs/aios/truth/project_state.yaml"
    route = truth["current_phase_route"]
    abort "current_phase_route missing" unless route.is_a?(Hash)
    route_policy = route["policy"]
    founder_policy = authority["founder_delegation_policy"]
    abort "route policy binding missing" unless route_policy.is_a?(Hash)
    abort "route policy path/hash drift" unless
      route_policy["path"] == founder_policy["path"] &&
      route_policy["sha256"] == founder_policy["sha256"] &&
      route_policy["version"] == founder_policy["version"]
  ' "$ROOT_DIR" "$TRUTH_PATH" || fail "current authority file binding invalid"
}

check_phase_predecessor_activation() {
  local truth_path="${1:-$TRUTH_PATH}"
  local requested_phase="${2:-CURRENT}"
  local requested_task="${3:-CURRENT}"
  local resource_action="${4:-STATE_AUDIT}"
  local truth_mode="${5:-CANONICAL_ONLY}"
  ruby -ryaml -rdigest -rjson -ropen3 -rpathname -e '
    truth_path = Pathname.new(ARGV.fetch(0))
    repo_root = Pathname.new(ARGV.fetch(1)).realpath
    requested_phase = ARGV.fetch(2)
    requested_task = ARGV.fetch(3)
    resource_action = ARGV.fetch(4)
    truth_mode = ARGV.fetch(5)
    canonical_truth_path = repo_root.join("docs/aios/truth/project_state.yaml")
    abort "unsupported phase predecessor Truth mode" unless %w[CANONICAL_ONLY TEST_FIXTURE].include?(truth_mode)
    if truth_mode == "CANONICAL_ONLY"
      abort "phase predecessor check requires canonical Truth path" unless
        truth_path.exist? && !truth_path.symlink? &&
        truth_path.realpath == canonical_truth_path.realpath
    end
    raw_truth = truth_path.binread
    truth_text = raw_truth.dup.force_encoding("UTF-8")
    abort "canonical Truth encoding invalid" unless truth_text.valid_encoding?
    syntax_tree = Psych.parse_stream(truth_text)
    reject_duplicate_keys = nil
    reject_duplicate_keys = lambda do |node, location|
      case node
      when Psych::Nodes::Mapping
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          abort "non-scalar YAML mapping key at #{location}" unless key_node.is_a?(Psych::Nodes::Scalar)
          key = key_node.value
          abort "duplicate YAML key at #{location}: #{key}" if seen.key?(key)
          seen[key] = true
          reject_duplicate_keys.call(value_node, "#{location}.#{key}")
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index do |child, index|
          reject_duplicate_keys.call(child, "#{location}[#{index}]")
        end
      else
        children = node.respond_to?(:children) ? node.children : nil
        children.each { |child| reject_duplicate_keys.call(child, location) } if children
      end
    end
    reject_duplicate_keys.call(syntax_tree, "Truth")
    truth = YAML.safe_load(truth_text, permitted_classes: [], permitted_symbols: [], aliases: false)
    project = truth.fetch("project")
    active = truth.fetch("active_work")
    task_id = active.fetch("current_task")
    phase = project.fetch("current_phase")
    phase_match = phase.match(/\AP(0|[1-9]|1[0-2])\z/)
    abort "current Phase must be exact P0 through P12" unless phase_match
    phase_number = Integer(phase_match[1], 10)
    target_phase = requested_phase == "CURRENT" ? phase : requested_phase
    target_phase_match = target_phase.match(/\AP(0|[1-9]|1[0-2])\z/)
    abort "requested target Phase must be exact P0 through P12" unless target_phase_match
    target_phase_number = Integer(target_phase_match[1], 10)
    target_task = requested_task == "CURRENT" ? task_id : requested_task
    allowed_resource_actions = %w[
      STATE_AUDIT ROUTE_ACTIVATION TASK_ACTIVATION BRANCH_CREATE WORKTREE_CREATE
      CANDIDATE_CREATE ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE
    ]
    abort "unsupported phase-sequence resource action" unless allowed_resource_actions.include?(resource_action)
    route_activation_precheck = resource_action == "ROUTE_ACTIVATION" &&
      target_phase_number == phase_number + 1
    abort "target Phase must equal canonical current Phase, except an exact next-Phase route precheck" unless
      target_phase == phase || route_activation_precheck
    route_phase = truth.dig("current_phase_route", "phase")
    abort "current route Phase does not equal canonical current Phase" unless route_phase == phase
    if target_task != "NONE"
      target_task_match = target_task.is_a?(String) && target_task.match(/\AAIOS-(P[0-9]+)-[A-Z0-9_]+\z/)
      abort "requested target Task identity invalid" unless target_task_match &&
        target_task_match[1] == target_phase
    elsif !%w[STATE_AUDIT ROUTE_ACTIVATION].include?(resource_action)
      abort "Task-scoped resource creation requires an explicit target Task"
    end
    preactivation_delegated_resource = false
    if resource_action == "STATE_AUDIT"
      abort "state audit target Task does not equal canonical current Task" unless target_task == task_id
    elsif resource_action == "ROUTE_ACTIVATION"
      abort "route activation precheck requires Task NONE" unless task_id == "NONE" && target_task == "NONE"
    else
      current_route = truth.fetch("current_phase_route")
      planned_ids = if current_route["schema_version"] == "phase-delegated-independent-task/v1"
                      abort "delegated independent route must not carry a legacy task_plan" if
                        current_route.key?("task_plan")
                      selected_task = current_route["selected_task"]
                      abort "delegated independent route requires exactly one selected Task" unless
                        selected_task.is_a?(Hash) && selected_task["task_id"].is_a?(String)
                      [selected_task["task_id"]]
                    else
                      Array(current_route["task_plan"]).each_with_object([]) do |item, ids|
                        ids << item["task_id"] if item.is_a?(Hash) && item["task_id"]
                      end
                    end
      abort "current route executable Task set is not closed" unless
        !planned_ids.empty? && planned_ids.uniq.length == planned_ids.length
      if %w[
        BRANCH_CREATE WORKTREE_CREATE ENGINEERING_EVIDENCE_CREATE TASK_AUTHORITY_CREATE
      ].include?(resource_action) &&
         current_route["schema_version"] == "phase-delegated-independent-task/v1" &&
         task_id == "NONE" && planned_ids == [target_task]
        selected_task = current_route.fetch("selected_task")
        reservation = truth.dig("phase_execution_envelope", "reserved")
        ready_active = truth.fetch("active_work")
        preactivation_delegated_resource =
          current_route["status"] == "AUTHORIZED_READY" &&
          current_route["execution_status"] == "PHASE_DELEGATED_TASK_READY" &&
          current_route["scheduling_status"] == "READY_FOR_MASTER_ACTIVATION" &&
          current_route["next_eligible_action"] == "MASTER_ACTIVATE_PHASE_DELEGATED_TASK" &&
          selected_task["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
          reservation.is_a?(Hash) &&
          reservation["task_id"] == target_task &&
          reservation["route_id"] == current_route["route_id"] &&
          reservation["status"] == "ELIGIBLE_NOT_ACTIVATED" &&
          reservation["authority"].nil? &&
          ready_active["task_resource_state"] == "NOT_CREATED_PHASE_DELEGATED_TASK_READY" &&
          ready_active["current_execution_authorization"].nil? &&
          ready_active["task_branch"].nil? && ready_active["task_worktree"].nil? &&
          ready_active["execution_evidence_root"].nil?
        abort "delegated READY resource precheck requires the exact unactivated reservation" unless
          preactivation_delegated_resource
      end
    end
    if resource_action == "TASK_ACTIVATION"
      abort "Task activation requires canonical Task NONE" unless task_id == "NONE"
      abort "Task activation target is not in the exact current route plan" unless planned_ids.include?(target_task)
    elsif resource_action == "TASK_AUTHORITY_CREATE"
      abort "Task authority creation requires the exact delegated READY reservation" unless
        preactivation_delegated_resource
    elsif preactivation_delegated_resource
      # Branch, worktree and Evidence are created only after this exact READY reservation check.
    elsif resource_action == "CANDIDATE_CREATE"
      abort "Task resource target does not equal the active canonical Task" unless
        task_id != "NONE" && target_task == task_id
      abort "active Task is not in the exact current route plan" unless planned_ids.include?(target_task)
      selected_task = current_route["selected_task"]
      reservation = truth.dig("phase_execution_envelope", "reserved")
      active_authority = active["authority_record"]
      closed_active_authority = active_authority.is_a?(Hash) &&
        active_authority.keys.sort == %w[byte_length path sha256] &&
        active_authority["path"].is_a?(String) && !active_authority["path"].empty? &&
        active_authority["byte_length"].is_a?(Integer) && active_authority["byte_length"].positive? &&
        active_authority["sha256"].is_a?(String) &&
        active_authority["sha256"].match?(/\A[0-9a-f]{64}\z/)
      exact_active_candidate_projection =
        current_route["schema_version"] == "phase-delegated-independent-task/v1" &&
        current_route["status"] == "ACTIVE" && current_route["execution_status"] == "ACTIVE" &&
        current_route["scheduling_status"] == "ACTIVE_PHASE_DELEGATED_TASK" &&
        selected_task.is_a?(Hash) && selected_task["task_id"] == target_task &&
        selected_task["status"] == "ACTIVE" && reservation.is_a?(Hash) &&
        reservation["task_id"] == target_task && reservation["route_id"] == current_route["route_id"] &&
        reservation["status"] == "ACTIVE" && closed_active_authority &&
        reservation["authority"] == active_authority &&
        active["current_task_status"] == "ACTIVE" &&
        active["task_resource_state"] == "ACTIVE_UNIQUE_PHASE_DELEGATED" &&
        active["current_execution_authorization"] == active_authority["path"] &&
        active["current_execution_authorization_sha256"] == active_authority["sha256"] &&
        [active["task_branch"], active["task_worktree"], active["execution_evidence_root"]].all? do |value|
          value.is_a?(String) && !value.empty?
        end
      abort "candidate creation requires the exact phase-delegated ACTIVE projection" unless
        exact_active_candidate_projection
    elsif !%w[STATE_AUDIT ROUTE_ACTIVATION].include?(resource_action)
      abort "Task resource target does not equal the active canonical Task" unless
        task_id != "NONE" && target_task == task_id
      abort "active Task is not in the exact current route plan" unless planned_ids.include?(target_task)
    end

    ledger = truth.fetch("strict_phase_gate_ledger")
    abort "strict phase Gate ledger schema invalid" unless ledger["schema_version"] == "1.0"
    abort "strict phase Gate ledger is not closed" unless ledger.keys.sort == %w[
      phase_route_authority phases rule schema_version sequence trust_model
    ].sort
    abort "strict Phase Gate trust model drift" unless
      ledger["trust_model"] ==
        "COOPERATIVE_LOCAL_EXACT_IDENTITY_WITHOUT_HOSTILE_PRINCIPAL_OR_CRYPTOGRAPHIC_ATTESTATION_CLAIM"
    expected_sequence = (0..12).map { |number| "P#{number}" }
    abort "strict phase sequence drift" unless ledger["sequence"] == expected_sequence
    phases = ledger.fetch("phases")
    abort "strict phase record set drift" unless phases.keys == expected_sequence

    git_capture = lambda do |*arguments|
      stdout, stderr, status = Open3.capture3("git", "-C", repo_root.to_s, *arguments)
      abort "git identity check failed: #{stderr.strip}" unless status.success?
      stdout
    end

    verify_commit_tree = lambda do |commit, tree|
      abort "accepted commit identity invalid" unless commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/)
      abort "accepted tree identity invalid" unless tree.is_a?(String) && tree.match?(/\A[0-9a-f]{40}\z/)
      actual_tree = git_capture.call("show", "-s", "--format=%T", commit).strip
      abort "accepted commit tree mismatch" unless actual_tree == tree
      _stdout, _stderr, status = Open3.capture3("git", "-C", repo_root.to_s, "merge-base", "--is-ancestor", commit, "HEAD")
      abort "accepted commit is not in canonical history" unless status.success?
    end

    verify_file = lambda do |identity|
      abort "Gate Evidence identity must be closed" unless identity.is_a?(Hash) &&
        identity.keys.sort == %w[byte_length path sha256]
      path = identity["path"]
      abort "Gate Evidence path must be absolute" unless path.is_a?(String) && Pathname.new(path).absolute?
      pathname = Pathname.new(path)
      abort "Gate Evidence must be a non-symlink regular file" unless pathname.file? && !pathname.symlink?
      abort "Gate Evidence path resolves through a symlink" unless pathname.realpath.to_s == pathname.cleanpath.to_s
      bytes = pathname.binread
      abort "Gate Evidence byte length mismatch" unless bytes.bytesize == identity["byte_length"]
      abort "Gate Evidence SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == identity["sha256"]
      bytes
    end

    verify_repository_file = lambda do |identity|
      abort "Exit Gate authority identity must be closed" unless identity.is_a?(Hash)
      path = identity.fetch("path")
      pathname = repo_root.join(path).cleanpath
      abort "Exit Gate authority escapes repository" unless pathname.to_s.start_with?("#{repo_root}/")
      abort "Exit Gate authority must be a non-symlink regular file" unless pathname.file? && !pathname.symlink?
      bytes = pathname.binread
      abort "Exit Gate authority byte length mismatch" if identity.key?("byte_length") && bytes.bytesize != identity["byte_length"]
      abort "Exit Gate authority SHA-256 mismatch" if identity.key?("sha256") &&
        Digest::SHA256.hexdigest(bytes) != identity["sha256"]
      bytes
    end

    phase_route_authority = ledger.fetch("phase_route_authority")
    expected_phase_route_authority = {
      "path" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "version" => "2.3",
      "section" => "## 9. Phase route",
      "section_byte_length" => 1869,
      "section_sha256" => "e636781630de5fb8d726b9d66f5520785753724fee942d7f06f1e08d8faad21a"
    }
    abort "strict Phase route authority identity drift" unless
      phase_route_authority == expected_phase_route_authority
    constitution_bytes = verify_repository_file.call({"path" => phase_route_authority["path"]})
    constitution_text = constitution_bytes.dup.force_encoding("UTF-8")
    abort "Strategic Constitution encoding invalid" unless constitution_text.valid_encoding?
    phase_route_header = "#{phase_route_authority.fetch("section")}\n"
    phase_route_start = constitution_text.index(phase_route_header)
    abort "strict Phase route authority section missing" unless phase_route_start
    phase_route_end = constitution_text.index(/^## /, phase_route_start + phase_route_header.bytesize)
    phase_route_section = constitution_text[phase_route_start...(phase_route_end || constitution_text.length)]
      .gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    abort "strict Phase route authority byte length mismatch" unless
      phase_route_section.bytesize == phase_route_authority["section_byte_length"]
    abort "strict Phase route authority SHA-256 mismatch" unless
      Digest::SHA256.hexdigest(phase_route_section) == phase_route_authority["section_sha256"]

    future_phase_specs = {
      "P2" => ["CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES",
               "Context benchmark beats simple retrieval baselines"],
      "P3" => ["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS",
               "Resume, isolation, permission and trace tests"],
      "P4" => ["VERIFIED_PATCHES_ON_CONTROLLED_REAL_TASKS",
               "Verified patches on controlled real tasks"],
      "P5" => ["ADVERSARIAL_AND_FAILURE_RECOVERY_EVIDENCE",
               "Adversarial and failure-recovery evidence"],
      "P6" => ["REPRODUCIBLE_BENCHMARK_REPORT", "Reproducible benchmark report"],
      "P7" => ["AB_OR_ABLATION_PRACTICAL_IMPROVEMENT_EVIDENCE",
               "A/B or ablation evidence of practical improvement"],
      "P8" => ["MULTI_AGENT_WINS_DECLARED_TRADEOFF",
               "Multi-Agent retained only if it wins on a declared tradeoff"],
      "P9" => ["GOVERNED_ORGANIZATION_EXPERIMENTS", "Governed organization experiments"],
      "P10" => ["SECOND_IMPLEMENTATION_USES_PLATFORM", "Second implementation can use the platform"],
      "P11" => ["SECOND_DOMAIN_EVIDENCE", "Evidence from a second domain"],
      "P12" => ["LONG_TERM_OUTCOME_FORMALLY_ACCEPTED", "Long-term outcome, not a current commitment"]
    }
    future_phase_specs.each do |phase_id, (item_id, exit_text)|
      phase_record = phases.fetch(phase_id)
      abort "#{phase_id} Exit Gate authority drift" unless phase_record["exit_gate_authority"] == {
        "source" => "STRICT_PHASE_ROUTE_AUTHORITY",
        "required_exit_evidence" => exit_text
      }
      abort "#{phase_id} required-item list drift" unless phase_record["required_item_ids"] == [item_id]
      abort "#{phase_id} required-item set drift" unless phase_record.fetch("required_items").keys == [item_id]
      row_marker = "| #{phase_id} "
      matching_rows = phase_route_section.lines.select do |line|
        line.start_with?(row_marker) && line.include?("| #{exit_text} |")
      end
      abort "#{phase_id} Exit Gate is not bound to exact Phase route row" unless matching_rows.length == 1
    end

    p0 = phases.fetch("P0")
    expected_p0_items = %w[CANONICAL_STATE MIGRATION_LEDGER BASELINE_PROTOCOL REVIEWABLE_WORKTREE_PLAN]
    abort "P0 required-item list drift" unless p0["required_item_ids"] == expected_p0_items
    abort "P0 required-item set drift" unless p0.fetch("required_items").keys == expected_p0_items
    abort "P0 required item is not accepted" unless p0["required_items"].all? do |item_id, item|
      item == {"status" => "ACCEPTED", "evidence_ref" => "P0_FOUNDER_PHASE_GATE"}
    end
    p0_gate = p0.fetch("founder_phase_gate")
    expected_p0_gate_keys = %w[accepted_checkpoint_commit accepted_checkpoint_tree byte_length commit decision_id path sha256 status storage]
    abort "P0 Founder Gate record is not closed" unless p0_gate.keys.sort == expected_p0_gate_keys
    abort "P0 Founder Gate is not PASS" unless p0_gate["status"] == "PASS" &&
      p0_gate["decision_id"] == "SOURCE-LENS-AIOS-P0-FOUNDER-GATE-20260711T125610Z" &&
      p0_gate["storage"] == "GIT_BLOB"
    p0_blob = git_capture.call("show", "#{p0_gate.fetch("commit")}:#{p0_gate.fetch("path")}").b
    abort "P0 Founder Gate byte length mismatch" unless p0_blob.bytesize == p0_gate["byte_length"]
    abort "P0 Founder Gate SHA-256 mismatch" unless Digest::SHA256.hexdigest(p0_blob) == p0_gate["sha256"]
    p0_text = p0_blob.dup.force_encoding("UTF-8")
    abort "P0 Founder Gate encoding invalid" unless p0_text.valid_encoding?
    [
      "decision: PASS",
      "decision_id: SOURCE-LENS-AIOS-P0-FOUNDER-GATE-20260711T125610Z",
      "current_gate_result: P0_GATE_PASS_BY_FOUNDER_DECISION",
      "approved_source_ref: #{p0_gate.fetch("accepted_checkpoint_commit")}"
    ].each { |marker| abort "P0 Founder Gate semantic marker missing" unless p0_text.lines.map(&:strip).include?(marker) }
    abort "P0 checkpoint commit drift" unless truth.dig("p0_baseline", "checkpoint_commit") == p0_gate["accepted_checkpoint_commit"]
    abort "P0 checkpoint tree drift" unless truth.dig("p0_baseline", "checkpoint_tree") == p0_gate["accepted_checkpoint_tree"]
    abort "P0 Gate ledger status drift" unless p0["status"] == "COMPLETE"

    p1 = phases.fetch("P1")
    expected_p1_items = %w[
      VERSIONED_TASKSPEC_AND_REPRESENTATIVE_TASK_SET
      REPRODUCIBLE_ENVIRONMENT_SNAPSHOTS
      REQUIRED_OBSERVABLE_ACTION_TRACES
      B0_B1_B2_COMMON_HARNESS_OR_COMPATIBILITY_ADAPTERS
      HIDDEN_SET_ACCESS_SEPARATION
      EVALUATOR_DISAGREEMENT_AND_FALSE_SUCCESS_CHARACTERIZATION
      REPRODUCIBLE_BASELINE_REPORT
      P2_CONTEXT_ENGINE_PREREGISTRATION
    ]
    abort "P1 required-item list drift" unless p1["required_item_ids"] == expected_p1_items
    p1_items = p1.fetch("required_items")
    abort "P1 required-item set drift" unless p1_items.keys == expected_p1_items

    exit_authority = p1.fetch("exit_gate_authority")
    abort "P1 Exit Gate authority identity drift" unless exit_authority == {
      "path" => "docs/aios/EVALUATION_PROTOCOL.md",
      "version" => "1.1",
      "section" => "## 12. P1 exit gate",
      "section_byte_length" => 567,
      "section_sha256" => "69dade6cd7e28a289004a799e1534909b59e8ab9007b3ababfb3172c77bccba3"
    }
    evaluation_bytes = verify_repository_file.call({"path" => exit_authority["path"]})
    evaluation_text = evaluation_bytes.dup.force_encoding("UTF-8")
    abort "Evaluation Protocol encoding invalid" unless evaluation_text.valid_encoding?
    header = "#{exit_authority.fetch("section")}\n"
    section_start = evaluation_text.index(header)
    abort "P1 Exit Gate section missing" unless section_start
    next_header = evaluation_text.index(/^## /, section_start + header.bytesize)
    section = evaluation_text[section_start...(next_header || evaluation_text.length)]
      .gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    abort "P1 Exit Gate section byte length mismatch" unless section.bytesize == exit_authority["section_byte_length"]
    abort "P1 Exit Gate section SHA-256 mismatch" unless Digest::SHA256.hexdigest(section) == exit_authority["section_sha256"]

    task_history = truth.fetch("task_history")
    accepted_history_statuses = %w[
      MASTER_TASK_GATE_ACCEPTED_COMPLETE
      FOUNDER_EXCEPTION_ACCEPTED_COMPLETE
      FOUNDER_GATE_ACCEPTED_COMPLETE
      FOUNDER_RESIDUAL_ACCEPTED_COMPLETE
      FOUNDER_RESIDUAL_ACCEPTED_SECURITY_CORRECTED_COMPLETE
    ]
    legacy_capabilities = {
      "REQUIRED_OBSERVABLE_ACTION_TRACES" => "OBSERVABLE_TRACE",
      "HIDDEN_SET_ACCESS_SEPARATION" => "HIDDEN_SET_PROTOCOL",
      "EVALUATOR_DISAGREEMENT_AND_FALSE_SUCCESS_CHARACTERIZATION" =>
        "EVALUATOR_DISAGREEMENT_AND_FALSE_SUCCESS_CHARACTERIZATION"
    }

    validate_gate_item = lambda do |phase_id, item_id, item|
      expected_item_keys = %w[acceptance_commit acceptance_tree gate_evidence status task_history_key task_id]
      abort "#{phase_id} Gate item is not closed: #{item_id}" unless item.is_a?(Hash) &&
        item.keys.sort == expected_item_keys
      evidence = item["gate_evidence"]
      abort "#{phase_id} Gate Evidence is not closed: #{item_id}" unless evidence.is_a?(Hash) &&
        evidence.keys.sort == %w[byte_length path receipt_type sha256]

      if item["status"] == "MISSING"
        abort "#{phase_id} missing Gate item retains an authority identity: #{item_id}" unless
          item["task_history_key"].nil? && item["task_id"].nil? &&
          item["acceptance_commit"].nil? && item["acceptance_tree"].nil? &&
          evidence.values.all?(&:nil?)
        next
      end

      abort "#{phase_id} Gate item status is invalid: #{item_id}" unless item["status"] == "ACCEPTED"
      task_id_value = item["task_id"]
      task_match = task_id_value.is_a?(String) && task_id_value.match(/\AAIOS-(P[0-9]+)-[A-Z0-9_]+\z/)
      abort "#{phase_id} accepted Gate Task identity invalid: #{item_id}" unless task_match &&
        task_match[1] == phase_id
      history_key = item["task_history_key"]
      abort "#{phase_id} accepted Gate history key invalid: #{item_id}" unless
        history_key.is_a?(String) && history_key.match?(/\Aaios_p[0-9]+_[0-9]{3}\z/)
      history = task_history.fetch(history_key)
      abort "#{phase_id} accepted Gate Task history mismatch: #{item_id}" unless history["task_id"] == task_id_value
      verify_commit_tree.call(item["acceptance_commit"], item["acceptance_tree"])
      receipt_type = evidence["receipt_type"]
      receipt_bytes = verify_file.call(evidence.slice("path", "byte_length", "sha256"))
      receipt = JSON.parse(receipt_bytes)

      case receipt_type
      when "STRICT_TASK_GATE_RECEIPT_V1"
        expected_receipt_keys = %w[
          accepted_commit accepted_tree decision evidence_manifest phase record_type
          required_item_id reviews schema_version task_id
        ]
        abort "strict Task Gate receipt is not closed: #{item_id}" unless
          receipt.keys.sort == expected_receipt_keys.sort
        manifest_identity = receipt["evidence_manifest"]
        manifest_bytes = verify_file.call(manifest_identity)
        reviews = receipt["reviews"]
        abort "strict Task Gate review set is not closed: #{item_id}" unless
          reviews.is_a?(Hash) && reviews.keys.sort == %w[cto quality security]
        reviewer_identities = []
        reviewer_run_ids = []
        reviews.each do |review_key, review_identity|
          review_path = review_identity["path"]
          review_root = "/Users/lijunpeng/Developer/.sourcelens-audit/independent-reviews/"
          abort "strict Task Gate review is outside the independent-review root: #{item_id}/#{review_key}" unless
            review_path.is_a?(String) && review_path.start_with?(review_root)
          review = JSON.parse(verify_file.call(review_identity))
          expected_review_keys = %w[
            candidate_commit candidate_tree evidence_manifest_sha256 required_item_id
            reviewed_at_utc reviewer_identity reviewer_role reviewer_run_id
            schema_version target_verdict task_id
          ]
          abort "strict Task Gate review is not closed: #{item_id}/#{review_key}" unless
            review.keys.sort == expected_review_keys.sort
          expected_role = {"cto" => "CTO", "security" => "SECURITY", "quality" => "QUALITY"}.fetch(review_key)
          abort "strict Task Gate review binding mismatch: #{item_id}/#{review_key}" unless
            review["schema_version"] == "strict-task-gate-review/v1" &&
            review["reviewer_role"] == expected_role &&
            review["reviewer_identity"].is_a?(String) &&
            !review["reviewer_identity"].strip.empty? &&
            review["reviewer_run_id"].is_a?(String) &&
            review["reviewer_run_id"].match?(/\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/) &&
            review["reviewed_at_utc"].is_a?(String) &&
            review["reviewed_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/) &&
            review["target_verdict"] == "PASS" &&
            review["task_id"] == task_id_value &&
            review["required_item_id"] == item_id &&
            review["candidate_commit"] == item["acceptance_commit"] &&
            review["candidate_tree"] == item["acceptance_tree"] &&
            review["evidence_manifest_sha256"] == Digest::SHA256.hexdigest(manifest_bytes)
          reviewer_identities << review["reviewer_identity"]
          reviewer_run_ids << review["reviewer_run_id"]
        end
        abort "strict Task Gate reviewers are not independent identities: #{item_id}" unless
          reviewer_identities.uniq.length == 3 && reviewer_run_ids.uniq.length == 3
        abort "strict Task Gate receipt schema mismatch: #{item_id}" unless
          receipt["schema_version"] == "strict-task-gate-receipt/v1" &&
          receipt["record_type"] == "sourcelens_aios_strict_task_gate_receipt" &&
          receipt["phase"] == phase_id &&
          receipt["task_id"] == task_id_value &&
          receipt["required_item_id"] == item_id &&
          receipt["decision"] == "PASS" &&
          receipt["accepted_commit"] == item["acceptance_commit"] &&
          receipt["accepted_tree"] == item["acceptance_tree"] &&
          receipt["evidence_manifest"] == manifest_identity
        abort "strict Task Gate history status mismatch: #{item_id}" unless
          accepted_history_statuses.include?(history["status"]) &&
          history["accepted_candidate_commit"] == item["acceptance_commit"] &&
          history["accepted_candidate_tree"] == item["acceptance_tree"]
      when "P1_219_EXACT_REVIEWED_BLOB_EXIT_READY_ADMISSION_RECEIPT_V1"
        expected_receipt_keys = %w[
          external_effects founder_authorization_token frozen_node20 original_reviews
          p2_experiment_executed p2_hold_released phase preserved_terminal_receipt
          record_type required_item_id reviewed_candidate reviewed_engineering_blobs
          route_id schema_version status targeted_verification task_id
        ]
        abort "P1-219 exact admission receipt is not closed" unless
          receipt.keys.sort == expected_receipt_keys.sort
        abort "P1-219 exact admission receipt identity mismatch" unless
          phase_id == "P1" &&
          item_id == "P2_CONTEXT_ENGINE_PREREGISTRATION" &&
          task_id_value == "AIOS-P1-219_DATASET_DERIVED_REPORT_BOUND_P2_CONTEXT_PREREGISTRATION" &&
          receipt["schema_version"] == "p1-219-exact-reviewed-blob-admission-receipt/v1" &&
          receipt["record_type"] == "sourcelens_aios_p1_219_exact_reviewed_blob_admission_receipt" &&
          receipt["status"] == "AUTHORIZED_FOR_EXACT_READMISSION_PENDING_FRESH_FINAL_REVIEW_AND_CANONICAL_VERIFY" &&
          receipt["phase"] == phase_id && receipt["task_id"] == task_id_value &&
          receipt["required_item_id"] == item_id &&
          receipt["route_id"] == history["route_id"] &&
          receipt["founder_authorization_token"] ==
            "AUTHORIZE_ONE_P1_EXIT_GATE_READY_STATE_COMPATIBILITY_AND_EXACT_P1_219_INTEGRATION_V1" &&
          receipt["p2_experiment_executed"] == false && receipt["p2_hold_released"] == false &&
          receipt["external_effects"] == {
            "network" => false, "provider" => false, "secret" => false,
            "remote" => false, "production" => false, "public" => false
          }

        reviewed = receipt.fetch("reviewed_candidate")
        abort "P1-219 reviewed candidate is not closed" unless
          reviewed.is_a?(Hash) && reviewed.keys.sort == %w[commit manifest tree]
        abort "P1-219 reviewed candidate identity drift" unless
          reviewed["commit"] == item["acceptance_commit"] &&
          reviewed["tree"] == item["acceptance_tree"] &&
          reviewed["commit"] == "231bf0eca104f66d3a0343b4ff7e3bc00420905e" &&
          reviewed["tree"] == "09be4786161a9b9c13716941bd2659d9a084a5c4"
        manifest_bytes = verify_file.call(reviewed.fetch("manifest"))
        manifest = JSON.parse(manifest_bytes)
        abort "P1-219 reviewed manifest binding drift" unless
          reviewed["manifest"] == {
            "path" => "/Users/lijunpeng/Developer/.sourcelens-audit/p1-dataset-derived-preregistration-strict-exit-20260805/task-1-p1-219/candidate-v1/P1_219_CANDIDATE_MANIFEST.json",
            "byte_length" => 3028,
            "sha256" => "1c84d75030d75082c2ace3dfc34dc0f58257f2ee6014d32455d6a3fa42e5a008"
          } &&
          manifest.dig("candidate", "commit") == reviewed["commit"] &&
          manifest.dig("candidate", "tree") == reviewed["tree"]

        expected_blobs = [
          ["evaluation-harness/evaluator/p1-219-dataset-derived-preregistration/generate.mjs", "100755", "3d05a7594660aa2acacff967c7b16ed43e274cfb", 954, "55eb3f86b3129678057af87d484d6aab2d67f024b0d503c69ad7c99603917d04"],
          ["evaluation-harness/evaluator/p1-219-dataset-derived-preregistration/lib.mjs", "100644", "8422ef61e8fa5d76467699db1282d08214accb22", 9428, "13c5fb7f65b0d86db80e14e2b226a5bc5f86ca9bb1d1552c6369351bba392a88"],
          ["evaluation-harness/evaluator/p1-219-dataset-derived-preregistration/test.mjs", "100755", "519b95faacb83d3d0d83a58b49622fadea86afae", 7032, "f8bbbe6fa80e48f4f8852ff72aea3a7852fe72bbd9a6c0dc8822ef4d8f2a0058"],
          ["evaluation-harness/evaluator/p1-219-dataset-derived-preregistration/verify.mjs", "100755", "adf80bcf20e3a5591091d7938f4390bd2589c904", 474, "624fdfdb2e5fea2267264341b4f671a3a47d373c5bb8b434395046074ddd016a"],
          ["evaluation-harness/reports/p1-219-dataset-derived-preregistration/P2_CONTEXT_ENGINE_PREREGISTRATION.json", "100644", "dfc74420fa5dfb2d50aac5110556d6e6a9df5dc4", 6531, "4a5976b0bdffb5646fcab2b22c53216ff3d09dceb454082474953fe41482156f"],
          ["scripts/verify-p1-219-dataset-derived-preregistration.sh", "100755", "7d0ba764d9e76d4f0abe357dcb8336b97134fec7", 664, "c705cd49e0df6067cbc782da2a49431edeb6036f8bfdb45371d7fbd0d325a53d"]
        ].map do |path, mode, blob, byte_length, sha256|
          {"path" => path, "mode" => mode, "git_blob_sha1" => blob,
           "byte_length" => byte_length, "sha256" => sha256}
        end
        abort "P1-219 reviewed engineering blob inventory drift" unless
          receipt["reviewed_engineering_blobs"] == expected_blobs
        expected_blobs.each do |blob|
          bytes = verify_repository_file.call(blob.slice("path", "byte_length", "sha256"))
          current_path = repo_root.join(blob["path"])
          current_mode = (current_path.stat.mode & 0o111).zero? ? "100644" : "100755"
          current_blob = git_capture.call("hash-object", "--", blob["path"]).strip
          reviewed_entry = git_capture.call("ls-tree", reviewed["commit"], "--", blob["path"]).strip.split
          abort "P1-219 current blob identity drift: #{blob['path']}" unless
            current_mode == blob["mode"] && current_blob == blob["git_blob_sha1"] &&
            Digest::SHA1.hexdigest("blob #{bytes.bytesize}\0".b + bytes) == blob["git_blob_sha1"]
          abort "P1-219 reviewed candidate blob identity drift: #{blob['path']}" unless
            reviewed_entry[0] == blob["mode"] && reviewed_entry[2] == blob["git_blob_sha1"]
        end

        reviews = receipt.fetch("original_reviews")
        abort "P1-219 original review set is not closed" unless
          reviews.is_a?(Hash) && reviews.keys.sort == %w[cto quality security]
        expected_roles = {"cto" => "CTO", "security" => "SECURITY", "quality" => "QUALITY"}
        reviews.each do |role, identity|
          abort "P1-219 original Review identity is not closed: #{role}" unless
            identity.is_a?(Hash) && identity.keys.sort == %w[byte_length path sha256 target_verdict]
          review = JSON.parse(verify_file.call(identity.slice("path", "byte_length", "sha256")))
          candidate_fields = %w[candidate exact_candidate].select { |field| review[field].is_a?(Hash) }
          abort "P1-219 original Review candidate binding is ambiguous: #{role}" unless candidate_fields.length == 1
          review_candidate = review.fetch(candidate_fields.fetch(0))
          abort "P1-219 original Review binding drift: #{role}" unless
            identity["target_verdict"] == "PASS" &&
            review["target_verdict"] == "PASS" && review["role"] == expected_roles.fetch(role) &&
            review_candidate["commit"] == reviewed["commit"] &&
            review_candidate["tree"] == reviewed["tree"] &&
            review.dig("candidate_manifest", "sha256") == reviewed.dig("manifest", "sha256")
        end

        terminal = receipt.fetch("preserved_terminal_receipt")
        terminal_bytes = verify_file.call(terminal)
        terminal_record = JSON.parse(terminal_bytes)
        abort "P1-219 preserved terminal receipt drift" unless
          terminal_record["task_id"] == task_id_value &&
          terminal_record["status"] == "TERMINAL_CANONICAL_MAKE_VERIFY_NON_PASS"

        node20 = receipt.fetch("frozen_node20")
        node_path = Pathname.new(node20.fetch("path"))
        abort "P1-219 frozen Node 20 identity is not closed" unless
          node20.keys.sort == %w[byte_length path sha256 version] &&
          node_path.file? && !node_path.symlink? && node_path.realpath == node_path.cleanpath
        node_bytes = node_path.binread
        node_version, node_stderr, node_status = Open3.capture3(node_path.to_s, "--version")
        abort "P1-219 frozen Node 20 identity drift: #{node_stderr.strip}" unless
          node_status.success? && node_version.strip == node20["version"] &&
          node20 == {
            "path" => "/usr/local/bin/node", "version" => "v20.17.0",
            "byte_length" => 193262272,
            "sha256" => "c5548e7a991a5c90170a29843ffc46df4643e29141f3cbb035f60295cf2bc882"
          } && node_bytes.bytesize == node20["byte_length"] &&
          Digest::SHA256.hexdigest(node_bytes) == node20["sha256"]

        abort "P1-219 targeted verification projection drift" unless
          receipt["targeted_verification"] == {
            "status" => "PASS", "positive_cases" => 1, "negative_cases" => 22,
            "false_accepts" => 0, "provider_requests" => 0, "secret_reads" => 0
          }
        abort "P1-219 accepted history status mismatch" unless
          accepted_history_statuses.include?(history["status"]) &&
          history["accepted_candidate_commit"] == item["acceptance_commit"] &&
          history["accepted_candidate_tree"] == item["acceptance_tree"]
      when "LEGACY_P1_035_TASK_GATE_RECEIPT"
        abort "legacy P1-035 receipt used for another Gate item" unless
          phase_id == "P1" && item_id == "VERSIONED_TASKSPEC_AND_REPRESENTATIVE_TASK_SET"
        abort "legacy P1-035 Gate receipt mismatch" unless
          receipt["task_id"] == task_id_value && receipt["status"] == "ACCEPTED" &&
          history["status"] == "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      when "LEGACY_P1_011_MASTER_GATE_DECISION"
        abort "legacy P1-011 receipt used for another Gate item" unless
          phase_id == "P1" && item_id == "REPRODUCIBLE_ENVIRONMENT_SNAPSHOTS"
        abort "legacy P1-011 Gate receipt mismatch" unless
          receipt["task_id"] == task_id_value &&
          receipt["decision"] == "ACCEPTED_FOR_LOCAL_GATE_INTEGRATION_PENDING_FINAL_CANONICAL_VERIFY" &&
          receipt["review_verdicts"] == {"cto" => "PASS", "security" => "PASS", "quality" => "PASS"} &&
          history["status"] == "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      when "LEGACY_CANONICAL_INTEGRATION_RECEIPT"
        expected_capability = legacy_capabilities[item_id]
        abort "legacy integration receipt used for an unsupported Gate item" unless phase_id == "P1" &&
          expected_capability
        accepted_capabilities = Array(receipt["accepted_capabilities"]) + Array(receipt["accepted_capability"])
        abort "legacy canonical integration receipt mismatch: #{item_id}" unless
          receipt["task_id"] == task_id_value &&
          receipt["status"] == "MASTER_TASK_GATE_ACCEPTED_COMPLETE" &&
          accepted_capabilities.include?(expected_capability) &&
          receipt.dig("canonical_integration", "commit") == item["acceptance_commit"] &&
          receipt.dig("canonical_integration", "tree") == item["acceptance_tree"] &&
          history["status"] == "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
      when "LEGACY_P1_099_FOUNDER_EXCEPTION_INTEGRATION_RECEIPT"
        abort "legacy P1-099 receipt used for another Gate item" unless
          phase_id == "P1" && item_id == "B0_B1_B2_COMMON_HARNESS_OR_COMPATIBILITY_ADAPTERS"
        abort "legacy P1-099 Founder exception receipt mismatch" unless
          receipt["accepted_capability"] == "B0_B1_B2_COMPATIBILITY_ADAPTERS" &&
          receipt["quality_review_rewritten_as_pass"] == false &&
          receipt.dig("canonical_integration", "commit") == item["acceptance_commit"] &&
          receipt.dig("canonical_integration", "tree") == item["acceptance_tree"] &&
          receipt.dig("canonical_integration", "canonical_make_verify_result") == "PASS" &&
          history["status"] == "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS" &&
          history.dig("founder_exception_integration", "integration_commit") == item["acceptance_commit"] &&
          history.dig("founder_exception_integration", "integration_tree") == item["acceptance_tree"]
      when "FOUNDER_DOCUMENTATION_SCOPE_RESIDUAL_ACCEPTANCE_INTEGRATION_RECEIPT"
        expected_receipt_keys = %w[
          accepted_report engineering_gate external_effects founder_residual_acceptance
          fresh_final_reviews integration phase_effect recorded_at_utc reviewed_candidate
          route_id schema_version status task_id
        ]
        abort "Founder residual Gate receipt is not closed: #{item_id}" unless
          receipt.keys.sort == expected_receipt_keys.sort
        abort "Founder residual Gate receipt identity mismatch: #{item_id}" unless
          receipt["schema_version"] == "p1-217-founder-residual-integration-receipt/v1" &&
          receipt["status"] == "FOUNDER_GATE_ACCEPTED_COMPLETE" &&
          receipt["task_id"] == task_id_value &&
          receipt["route_id"] == history["route_id"] &&
          history["status"] == "FOUNDER_GATE_ACCEPTED_COMPLETE"

        reviewed = receipt.fetch("reviewed_candidate")
        abort "Founder residual reviewed candidate is not closed: #{item_id}" unless
          reviewed.is_a?(Hash) && reviewed.keys.sort == %w[commit evidence_tag manifest tree]
        reviewed_manifest = reviewed.fetch("manifest")
        verify_file.call(reviewed_manifest)
        abort "Founder residual reviewed candidate binding mismatch: #{item_id}" unless
          reviewed["commit"] == history["reviewed_candidate_commit"] &&
          reviewed["tree"] == history["reviewed_candidate_tree"] &&
          reviewed_manifest == {
            "path" => history["candidate_manifest_path"],
            "byte_length" => history["candidate_manifest_byte_length"],
            "sha256" => history["candidate_manifest_sha256"]
          }

        residual = receipt.fetch("founder_residual_acceptance")
        expected_residual_keys = %w[
          accepted_residual authorization_token byte_length candidate_bytes_modified_after_review
          capability_credit_from_residual_acceptance path quality_non_pass_preserved
          quality_non_pass_rewritten_as_pass sha256
        ]
        abort "Founder residual acceptance is not closed: #{item_id}" unless
          residual.is_a?(Hash) && residual.keys.sort == expected_residual_keys.sort
        decision_bytes = verify_file.call(residual.slice("path", "byte_length", "sha256"))
        decision_text = decision_bytes.dup.force_encoding("UTF-8")
        token_lines = decision_text.lines.map(&:strip).select { |line| line.start_with?("authorization_token=") }
        abort "Founder residual authorization is not exact and anchored: #{item_id}" unless
          decision_text.valid_encoding? &&
          token_lines == ["authorization_token=#{residual.fetch("authorization_token")}"] &&
          residual["authorization_token"] == history.dig("founder_residual_acceptance", "decision", "authorization_token") &&
          residual["path"] == history.dig("founder_residual_acceptance", "decision", "path") &&
          residual["byte_length"] == history.dig("founder_residual_acceptance", "decision", "byte_length") &&
          residual["sha256"] == history.dig("founder_residual_acceptance", "decision", "sha256") &&
          residual["accepted_residual"] == "EXACT_DOCUMENTATION_ONLY_README_OUTSIDE_PRIOR_CORRECTION_ALLOWLIST" &&
          residual["quality_non_pass_preserved"] == true &&
          residual["quality_non_pass_rewritten_as_pass"] == false &&
          residual["candidate_bytes_modified_after_review"] == false &&
          residual["capability_credit_from_residual_acceptance"] == 0

        reviews = receipt.fetch("fresh_final_reviews")
        abort "Founder residual review set is not closed: #{item_id}" unless
          reviews.is_a?(Hash) && reviews.keys.sort == %w[cto quality security]
        expected_review_verdicts = {"cto" => "PASS", "security" => "PASS", "quality" => "NON_PASS"}
        expected_review_verdicts.each do |role, verdict|
          review_identity = reviews.fetch(role)
          expected_keys = %w[byte_length path sha256 target_verdict]
          expected_keys << "sole_blocker" if role == "quality"
          abort "Founder residual Review identity is not closed: #{item_id}/#{role}" unless
            review_identity.is_a?(Hash) && review_identity.keys.sort == expected_keys.sort
          review = JSON.parse(verify_file.call(review_identity.slice("path", "byte_length", "sha256")))
          abort "Founder residual Review binding mismatch: #{item_id}/#{role}" unless
            review_identity["target_verdict"] == verdict &&
            review_identity["path"] == history.fetch("#{role}_review_path") &&
            review_identity["byte_length"] == history.fetch("#{role}_review_byte_length") &&
            review_identity["sha256"] == history.fetch("#{role}_review_sha256") &&
            review["TARGET_VERDICT"] == verdict &&
            review["task_id"] == task_id_value &&
            review.dig("candidate", "commit") == reviewed["commit"] &&
            review.dig("candidate", "tree") == reviewed["tree"]
        end
        abort "Founder residual Quality blocker drift: #{item_id}" unless
          reviews.dig("quality", "sole_blocker") == "DOCUMENTATION_PATH_OUTSIDE_PRIOR_EXACT_CORRECTION_ALLOWLIST"

        report = receipt.fetch("accepted_report")
        verify_file.call(report)
        integration = receipt.fetch("integration")
        abort "Founder residual integration or report binding mismatch: #{item_id}" unless
          report == history["accepted_report"] &&
          integration["commit"] == item["acceptance_commit"] &&
          integration["tree"] == item["acceptance_tree"] &&
          integration["reviewed_tree_equals_integrated_tree"] == true &&
          integration["canonical_make_verify"] == "PASS" &&
          integration["canonical_make_verify_invocations"] == 1 &&
          history["accepted_candidate_commit"] == item["acceptance_commit"] &&
          history["accepted_candidate_tree"] == item["acceptance_tree"] &&
          history["quality_target_verdict"] == "NON_PASS" &&
          history.dig("founder_residual_acceptance", "review_non_pass_preserved") == true &&
          history.dig("founder_residual_acceptance", "review_non_pass_rewritten_as_pass") == false
        abort "Founder residual Gate external effects are not closed: #{item_id}" unless
          receipt.fetch("external_effects") == {
            "network" => false, "provider" => false, "secret" => false,
            "remote" => false, "production" => false, "public" => false
          }
      else
        abort "unsupported Gate receipt type: #{receipt_type.inspect}"
      end
    end

    p1_items.each { |item_id, item| validate_gate_item.call("P1", item_id, item) }

    validate_founder_phase_gate = lambda do |phase_id, phase_record, required_ids|
      gate = phase_record.fetch("founder_phase_gate")
      expected_gate_keys = %w[byte_length decision_id path sha256 status]
      abort "#{phase_id} Founder Phase Gate record is not closed" unless
        gate.is_a?(Hash) && gate.keys.sort == expected_gate_keys
      if phase_record["status"] == "INCOMPLETE"
        abort "#{phase_id} incomplete Founder Gate identity must remain null" unless gate == {
          "status" => "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
          "decision_id" => nil,
          "path" => nil,
          "byte_length" => nil,
          "sha256" => nil
        }
        next
      end

      if phase_record["status"] == "EXIT_GATE_READY"
        abort "#{phase_id} Exit-Gate-ready Founder decision identity must remain null" unless gate == {
          "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION",
          "decision_id" => nil,
          "path" => nil,
          "byte_length" => nil,
          "sha256" => nil
        }
        next
      end

      abort "#{phase_id} Gate lifecycle status is invalid" unless phase_record["status"] == "COMPLETE"

      abort "#{phase_id} Founder Phase Gate is not PASS" unless gate["status"] == "PASS"
      receipt = JSON.parse(verify_file.call(gate.slice("path", "byte_length", "sha256")))
      expected_receipt_keys = %w[
        authorization_token canonical_commit canonical_tree decision decision_id phase
        founder_decision record_type required_item_receipts schema_version
      ]
      abort "#{phase_id} Founder Phase Gate receipt is not closed" unless
        receipt.keys.sort == expected_receipt_keys.sort
      founder_decision_path = receipt.dig("founder_decision", "path")
      founder_attachment_root = "/Users/lijunpeng/.codex/attachments/"
      abort "#{phase_id} Founder Phase Gate decision is not a Founder-provided attachment" unless
        founder_decision_path.is_a?(String) &&
        founder_decision_path.start_with?(founder_attachment_root)
      founder_decision = JSON.parse(verify_file.call(receipt["founder_decision"]))
      expected_decision_keys = %w[
        authority authorization_token canonical_commit canonical_tree decision decision_id
        phase record_type schema_version source_kind
      ]
      abort "#{phase_id} Founder Phase Gate decision is not closed" unless
        founder_decision.keys.sort == expected_decision_keys.sort
      abort "#{phase_id} Founder Phase Gate receipt schema mismatch" unless
        receipt["schema_version"] == "strict-founder-phase-gate-receipt/v1" &&
        receipt["record_type"] == "sourcelens_aios_strict_founder_phase_gate_receipt" &&
        receipt["phase"] == phase_id &&
        receipt["decision"] == "PASS" &&
        receipt["decision_id"] == gate["decision_id"] &&
        receipt["authorization_token"].is_a?(String) &&
        receipt["authorization_token"].match?(/\AAUTHORIZE_#{Regexp.escape(phase_id)}_[A-Z0-9_]+\z/)
      abort "#{phase_id} Founder Phase Gate decision binding mismatch" unless
        founder_decision["schema_version"] == "strict-founder-phase-gate-decision/v1" &&
        founder_decision["record_type"] == "sourcelens_aios_strict_founder_phase_gate_decision" &&
        founder_decision["authority"] == "HUMAN_FOUNDER" &&
        founder_decision["source_kind"] == "FOUNDER_PROVIDED_CODEX_ATTACHMENT" &&
        founder_decision["phase"] == phase_id &&
        founder_decision["decision"] == "PASS" &&
        founder_decision["decision_id"] == receipt["decision_id"] &&
        founder_decision["authorization_token"] == receipt["authorization_token"] &&
        founder_decision["canonical_commit"] == receipt["canonical_commit"] &&
        founder_decision["canonical_tree"] == receipt["canonical_tree"]
      required_receipts = receipt["required_item_receipts"]
      abort "#{phase_id} Founder Gate required-item receipt set drift" unless
        required_receipts.is_a?(Hash) && required_receipts.keys == required_ids
      required_ids.each do |item_id|
        abort "#{phase_id} Founder Gate item receipt identity drift: #{item_id}" unless
          required_receipts[item_id] == phase_record.dig("required_items", item_id, "gate_evidence", "sha256")
      end
      verify_commit_tree.call(receipt["canonical_commit"], receipt["canonical_tree"])
    end

    accepted_count = p1_items.values.count { |item| item["status"] == "ACCEPTED" }
    derived_completion = {
      "completed" => accepted_count,
      "total" => expected_p1_items.length,
      "percent" => (accepted_count * 100.0 / expected_p1_items.length).then { |value| value == value.to_i ? value.to_i : value }
    }
    abort "P1 derived completion drift" unless p1["derived_completion"] == derived_completion
    abort "P1 partial-exit completion drift" unless truth.dig("p1_partial_exit", "strict_completion") == derived_completion
    missing_ids = p1_items.each_with_object([]) do |(item_id, item), result|
      result << item_id unless item["status"] == "ACCEPTED"
    end
    abort "P1 missing-item projection drift" unless truth.dig("p1_partial_exit", "missing_exit_items") == missing_ids
    if missing_ids.empty?
      expected_p1_status = p1.dig("founder_phase_gate", "status") == "PASS" ? "COMPLETE" : "EXIT_GATE_READY"
      abort "P1 all-accepted Gate lifecycle status drift" unless p1["status"] == expected_p1_status
    else
      abort "P1 incomplete ledger status drift" unless p1["status"] == "INCOMPLETE"
    end
    validate_founder_phase_gate.call("P1", p1, expected_p1_items)
    p1_gate = p1.fetch("founder_phase_gate")
    future_phase_specs.each do |phase_id, (item_id, _exit_text)|
      phase_record = phases.fetch(phase_id)
      item = phase_record.fetch("required_items").fetch(item_id)
      validate_gate_item.call(phase_id, item_id, item)
      expected_status = item["status"] == "ACCEPTED" ? "COMPLETE" : "INCOMPLETE"
      abort "#{phase_id} derived Gate status drift" unless phase_record["status"] == expected_status
      validate_founder_phase_gate.call(phase_id, phase_record, [item_id])
    end

    unless task_id == "NONE"
      task_match = task_id.match(/\AAIOS-(P[0-9]+)-/)
      abort "active Task id has no phase identity" unless task_match
      abort "active Task phase does not match current Phase" unless task_match[1] == phase
    end

    earliest_incomplete_phase = phases.keys
      .select { |phase_id| phase_id.match?(/\AP(?:0|[1-9]|1[0-2])\z/) && phases[phase_id]["status"] != "COMPLETE" }
      .min_by { |phase_id| Integer(phase_id.delete_prefix("P"), 10) }
    if earliest_incomplete_phase
      earliest_incomplete_number = Integer(earliest_incomplete_phase.delete_prefix("P"), 10)
      abort "canonical current Phase advanced beyond the earliest incomplete Phase" if phase_number > earliest_incomplete_number
      ((earliest_incomplete_number + 1)..12).each do |later_number|
        entry_status = project["p#{later_number}_entry_status"]
        next if entry_status.nil?
        abort "later Phase P#{later_number} must remain HOLD while #{earliest_incomplete_phase} is incomplete" unless
          entry_status.is_a?(String) &&
          (entry_status.start_with?("HOLD_") || entry_status == "NOT_AUTHORIZED")
      end
    end

    if target_phase_number >= 1
      abort "P0 must be strictly COMPLETE before P1 scheduling" unless
        project["p0_status"] == "COMPLETE" && p0["status"] == "COMPLETE"
    end

    if target_phase_number >= 2
      expected_completion = {"completed" => 8, "total" => 8, "percent" => 100}
      abort "P1 is not strictly 8/8 complete" unless derived_completion == expected_completion
      abort "P1 closed Gate ledger is not COMPLETE" unless p1["status"] == "COMPLETE"
      abort "P1 Phase Gate PASS is not recorded" unless p1_gate["status"] == "PASS" &&
        truth.dig("p1_partial_exit", "phase_pass_claimed") == true
      abort "P1 100 percent completion is not recorded" unless
        truth.dig("p1_partial_exit", "completion_100_percent_claimed") == true
      abort "P1 canonical execution status is not strict complete" unless
        project["p1_execution_status"] == "COMPLETE_STRICT_8_OF_8_100_PERCENT"
    end

    if target_phase_number >= 3
      (2...target_phase_number).each do |predecessor_number|
        predecessor_id = "P#{predecessor_number}"
        predecessor = phases.fetch(predecessor_id)
        abort "#{predecessor_id} predecessor Gate is not COMPLETE" unless predecessor["status"] == "COMPLETE"
        required_ids = predecessor.fetch("required_item_ids")
        required_items = predecessor.fetch("required_items")
        abort "#{predecessor_id} predecessor required-item set is empty" unless required_ids.is_a?(Array) && !required_ids.empty?
        abort "#{predecessor_id} predecessor required-item set drift" unless required_items.keys == required_ids
        required_items.each do |item_id, item|
          validate_gate_item.call(predecessor_id, item_id, item)
          abort "#{predecessor_id} predecessor required item is not accepted: #{item_id}" unless
            item["status"] == "ACCEPTED"
        end
        validate_founder_phase_gate.call(predecessor_id, predecessor, required_ids)
      end
    end
  ' "$truth_path" "$ROOT_DIR" "$requested_phase" "$requested_task" "$resource_action" "$truth_mode" \
    || fail "strict phase predecessor activation invalid"
}

check_founder_knowledge_sync_state() {
  local validation_mode="${1:-DEEP}"
  local truth_path="${2:-$TRUTH_PATH}"
  local truth_scope="${3:-CANONICAL_ONLY}"
  ruby -ryaml -rdigest -rjson -rpathname -rpsych -rshellwords -e '
    repo_root = Pathname.new(ARGV.fetch(0)).realpath
    validation_mode = ARGV.fetch(1)
    abort "Founder Knowledge sync validation mode invalid" unless %w[STRUCTURAL_ONLY DEEP].include?(validation_mode)
    deep_validation = validation_mode == "DEEP"
    truth_path = Pathname.new(ARGV.fetch(2))
    truth_scope = ARGV.fetch(3)
    abort "Founder Knowledge sync Truth scope invalid" unless %w[CANONICAL_ONLY TEST_FIXTURE].include?(truth_scope)
    canonical_truth_path = repo_root.join("docs/aios/truth/project_state.yaml")
    abort "Founder Knowledge sync requires canonical Truth" if
      truth_scope == "CANONICAL_ONLY" &&
      (!truth_path.exist? || truth_path.symlink? || truth_path.realpath != canonical_truth_path.realpath)
    abort "Founder Knowledge sync Truth fixture missing or symlinked" unless
      truth_path.file? && !truth_path.symlink?
    truth_text = truth_path.binread.force_encoding("UTF-8")
    abort "Founder Knowledge sync Truth encoding invalid" unless truth_text.valid_encoding?
    syntax_tree = Psych.parse_stream(truth_text)
    reject_duplicates = nil
    reject_duplicates = lambda do |node, location|
      case node
      when Psych::Nodes::Mapping
        seen = {}
        node.children.each_slice(2) do |key_node, value_node|
          abort "non-scalar YAML key at #{location}" unless key_node.is_a?(Psych::Nodes::Scalar)
          key = key_node.value
          abort "duplicate YAML key at #{location}: #{key}" if seen.key?(key)
          seen[key] = true
          reject_duplicates.call(value_node, "#{location}.#{key}")
        end
      when Psych::Nodes::Sequence
        node.children.each_with_index { |child, index| reject_duplicates.call(child, "#{location}[#{index}]") }
      else
        children = node.respond_to?(:children) ? node.children : nil
        children.each { |child| reject_duplicates.call(child, location) } if children
      end
    end
    reject_duplicates.call(syntax_tree, "Truth")
    truth = YAML.safe_load(truth_text, permitted_classes: [], permitted_symbols: [], aliases: false)
    sync = truth.fetch("founder_knowledge_sync")
    expected_sync_keys = %w[
      allowed_statuses engineering_blocking events latest_event_id non_authoritative
      inherited_knowledge_compatibility schema_version trust_model vault_path
    ]
    abort "Founder Knowledge sync ledger is not closed" unless sync.keys.sort == expected_sync_keys.sort
    statuses = %w[
      PENDING_CANDIDATE PENDING_REVIEW REVIEWED_PASS_PENDING_IMPORT NON_PASS
      IMPORTED OUTDATED NO_MATERIAL_KNOWLEDGE_DELTA
    ]
    abort "Founder Knowledge sync schema drift" unless
      sync["schema_version"] == "1.0" &&
      sync["trust_model"] ==
        "COOPERATIVE_LOCAL_APPEND_CHAIN_WITH_CANONICAL_GIT_HISTORY_NO_HOSTILE_PRINCIPAL_OR_EXTERNAL_CHECKPOINT_CLAIM" &&
      sync["vault_path"] == "/Users/lijunpeng/Documents/AIOS-Founder-Knowledge-Vault" &&
      sync["non_authoritative"] == true &&
      sync["engineering_blocking"] == false &&
      sync["allowed_statuses"] == statuses
    events = sync["events"]
    abort "Founder Knowledge sync event ledger must be nonempty" unless events.is_a?(Array) && !events.empty?
    event_ids = events.map { |event| event["event_id"] }
    abort "Founder Knowledge sync event ids must be unique" unless event_ids.uniq.length == event_ids.length
    abort "Founder Knowledge latest event drift" unless sync["latest_event_id"] == event_ids.last
    abort "Founder Knowledge genesis event drift" unless
      event_ids.first == "FKS-20260728-STRICT-PHASE-SEQUENCE-AND-KNOWLEDGE-SYNC"

    canonicalize = nil
    canonicalize = lambda do |value|
      case value
      when Hash
        value.keys.sort.to_h { |key| [key, canonicalize.call(value[key])] }
      when Array
        value.map { |item| canonicalize.call(item) }
      else
        value
      end
    end

    exact_keys = lambda do |value, keys, label|
      abort "#{label} is not a closed object" unless
        value.is_a?(Hash) && value.keys.sort == keys.sort
      value
    end

    duplicate_rejecting_hash = Class.new(Hash) do
      def []=(key, value)
        raise "duplicate JSON key: #{key}" if key?(key)
        super
      end
    end
    parse_closed_json = lambda do |bytes, label|
      JSON.parse(bytes, object_class: duplicate_rejecting_hash)
    rescue JSON::ParserError, RuntimeError => error
      abort "#{label} JSON is invalid or ambiguous: #{error.message}"
    end

    validate_identity = lambda do |identity, label, allow_null|
      abort "#{label} identity is not closed" unless identity.is_a?(Hash) &&
        identity.keys.sort == %w[byte_length path sha256]
      if identity.values.all?(&:nil?)
        abort "#{label} identity may not be null" unless allow_null
        next nil
      end
      abort "#{label} identity is partially null" if identity.values.any?(&:nil?)
      path = identity["path"]
      abort "#{label} path must be absolute" unless path.is_a?(String) && Pathname.new(path).absolute?
      abort "#{label} byte length invalid" unless
        identity["byte_length"].is_a?(Integer) && identity["byte_length"] >= 0
      abort "#{label} SHA-256 invalid" unless
        identity["sha256"].is_a?(String) && identity["sha256"].match?(/\A[0-9a-f]{64}\z/)
      pathname = Pathname.new(path)
      abort "#{label} path must be normalized" unless pathname.cleanpath.to_s == path
      next "".b unless deep_validation
      abort "#{label} must be a non-symlink regular file" unless pathname.file? && !pathname.symlink?
      abort "#{label} path resolves through a symlink" unless pathname.realpath.to_s == pathname.cleanpath.to_s
      bytes = pathname.binread
      abort "#{label} byte length mismatch" unless bytes.bytesize == identity["byte_length"]
      abort "#{label} SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == identity["sha256"]
      bytes
    end

    compatibility = exact_keys.call(
      sync["inherited_knowledge_compatibility"],
      %w[
        activation_parent authorization_token entries founder_packet route_id
        schema_version status structured_decision
      ],
      "Founder Knowledge inherited compatibility declaration"
    )
    abort "Founder Knowledge inherited compatibility declaration schema drift" unless
      compatibility["schema_version"] == "1.0" &&
      compatibility["status"] == "FOUNDER_AUTHORIZED_EXACT_CLOSED_COMPATIBILITY"
    authorization_token = compatibility["authorization_token"]
    route_id = compatibility["route_id"]
    abort "Founder Knowledge inherited compatibility authorization invalid" unless
      authorization_token.is_a?(String) &&
      route_id.is_a?(String) &&
      authorization_token == "AUTHORIZE_#{route_id}" &&
      route_id.match?(/\AP1_[A-Z0-9_]+_ROUTE_V[1-9][0-9]*\z/)
    activation_parent = exact_keys.call(
      compatibility["activation_parent"], %w[commit tree],
      "Founder Knowledge inherited compatibility activation parent"
    )
    abort "Founder Knowledge inherited compatibility parent identity invalid" unless
      activation_parent.values.all? { |value| value.is_a?(String) && value.match?(/\A[0-9a-f]{40}\z/) }
    actual_parent_tree = `git -C #{repo_root.to_s.shellescape} show -s --format=%T #{activation_parent["commit"].shellescape} 2>/dev/null`.strip
    abort "Founder Knowledge inherited compatibility parent commit/tree mismatch" unless
      $?.success? && actual_parent_tree == activation_parent["tree"]
    system("git", "-C", repo_root.to_s, "merge-base", "--is-ancestor", activation_parent["commit"], "HEAD",
           out: File::NULL, err: File::NULL)
    abort "Founder Knowledge inherited compatibility parent is not canonical ancestry" unless $?.success?

    founder_packet = exact_keys.call(
      compatibility["founder_packet"], %w[byte_length path sha256],
      "Founder Knowledge inherited compatibility Founder packet"
    )
    structured_decision_identity = exact_keys.call(
      compatibility["structured_decision"], %w[byte_length path sha256],
      "Founder Knowledge inherited compatibility structured decision"
    )
    founder_packet_bytes = validate_identity.call(
      founder_packet, "Founder Knowledge inherited compatibility Founder packet", false
    )
    structured_decision_bytes = validate_identity.call(
      structured_decision_identity,
      "Founder Knowledge inherited compatibility structured decision", false
    )
    if deep_validation
      packet_text = founder_packet_bytes.dup.force_encoding("UTF-8")
      abort "Founder Knowledge inherited compatibility Founder packet encoding invalid" unless
        packet_text.valid_encoding?
      token_declarations = packet_text.scan(/^authorization_token=([A-Z0-9_]+)$/).flatten
      all_authorization_tokens = packet_text.scan(/\bAUTHORIZE_[A-Z0-9_]+\b/)
      abort "Founder Knowledge inherited compatibility Founder packet authorization is ambiguous" unless
        token_declarations == [authorization_token] && all_authorization_tokens == [authorization_token]
      decision = parse_closed_json.call(
        structured_decision_bytes,
        "Founder Knowledge inherited compatibility structured decision"
      )
      expected_decision_keys = %w[
        activation_parent authorization_token automatic_entries automatic_entry claim_boundary
        envelope external_effects goal_identity ordered_tasks phase record_type route_id
        schema_version source_founder_packet_identity
      ]
      exact_keys.call(decision, expected_decision_keys,
                      "Founder Knowledge inherited compatibility structured decision")
      abort "Founder Knowledge inherited compatibility structured decision is not canonical JSON" unless
        JSON.generate(canonicalize.call(decision)).b + "\n" == structured_decision_bytes.b
      source_packet_identity = exact_keys.call(
        decision["source_founder_packet_identity"],
        %w[authorization_token byte_length path sha256],
        "Founder Knowledge inherited compatibility structured source packet"
      )
      abort "Founder Knowledge inherited compatibility structured decision binding mismatch" unless
        decision["schema_version"] == "1.1" &&
        decision["record_type"] == "founder_phase_route_decision" &&
        decision["phase"] == "P1" &&
        decision["authorization_token"] == authorization_token &&
        decision["route_id"] == route_id &&
        decision["activation_parent"] == activation_parent &&
        source_packet_identity == founder_packet.merge("authorization_token" => authorization_token)
    end

    compatibility_entries = compatibility["entries"]
    expected_compatibility_types = %w[
      EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL
      ALTERNATE_FOUNDER_KNOWLEDGE_REVIEW_V2
      FOUNDER_KNOWLEDGE_REVIEW_V1
      FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1
    ]
    abort "Founder Knowledge inherited compatibility entry set is not closed" unless
      compatibility_entries.is_a?(Array) &&
      compatibility_entries.length == 4 &&
      compatibility_entries.map { |entry| entry["compatibility_type"] } == expected_compatibility_types
    expected_schema_by_type = {
      "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL" => "p1-168-terminal-receipt/v1",
      "ALTERNATE_FOUNDER_KNOWLEDGE_REVIEW_V2" => "founder-knowledge-review/v2",
      "FOUNDER_KNOWLEDGE_REVIEW_V1" => "founder-knowledge-review/v1",
      "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1" => "1.0"
    }
    expected_anomaly_by_type = {
      "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL" =>
        "STORED_EVENT_HASH_EQUALS_RETAINED_TERMINAL_RECEIPT_SHA_AND_PRE_CANDIDATE_RECEIPT_RETAINED",
      "ALTERNATE_FOUNDER_KNOWLEDGE_REVIEW_V2" => "EXACT_LEGACY_CLOSED_V2_REVIEW_KEYSET",
      "FOUNDER_KNOWLEDGE_REVIEW_V1" => "EXACT_LEGACY_V1_REVIEW_SCHEMA",
      "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1" => "EXACT_LEGACY_V1_IMPORT_RECEIPT_SCHEMA"
    }
    compatibility_objects = {}
    event_by_id = events.to_h { |event| [event["event_id"], event] }
    compatibility_entries.each do |entry|
      exact_keys.call(
        entry,
        %w[
          anomaly_type calculated_event_sha256 compatibility_type event_ids founder_packet
          object object_schema_version stored_event_sha256
        ],
        "Founder Knowledge inherited compatibility entry"
      )
      compatibility_type = entry["compatibility_type"]
      abort "Founder Knowledge inherited compatibility type unsupported" unless
        expected_schema_by_type.key?(compatibility_type)
      abort "Founder Knowledge inherited compatibility anomaly drift" unless
        entry["anomaly_type"] == expected_anomaly_by_type.fetch(compatibility_type)
      abort "Founder Knowledge inherited compatibility schema drift" unless
        entry["object_schema_version"] == expected_schema_by_type.fetch(compatibility_type)
      abort "Founder Knowledge inherited compatibility packet projection drift" unless
        entry["founder_packet"] == founder_packet
      event_ids_for_entry = entry["event_ids"]
      expected_event_count = compatibility_type == "FOUNDER_KNOWLEDGE_REVIEW_V1" ? 2 : 1
      abort "Founder Knowledge inherited compatibility event set invalid" unless
        event_ids_for_entry.is_a?(Array) &&
        event_ids_for_entry.length == expected_event_count &&
        event_ids_for_entry.uniq == event_ids_for_entry &&
        event_ids_for_entry.all? { |event_id| event_id.is_a?(String) && event_id.match?(/\AFKS-[A-Z0-9-]+\z/) }
      object = exact_keys.call(
        entry["object"], %w[byte_length file_type path sha256],
        "Founder Knowledge inherited compatibility object"
      )
      abort "Founder Knowledge inherited compatibility object type drift" unless
        object["file_type"] == "REGULAR_FILE_NON_SYMLINK"
      object_identity = object.reject { |key, _value| key == "file_type" }
      if deep_validation
        packet_bound_literals = event_ids_for_entry + [
          object["path"], object["byte_length"].to_s, object["sha256"]
        ]
        packet_bound_literals.concat(
          [entry["stored_event_sha256"], entry["calculated_event_sha256"]].compact
        )
        abort "Founder Knowledge inherited compatibility entry is not bound by the exact Founder packet" unless
          packet_bound_literals.all? { |literal| founder_packet_bytes.include?("`#{literal}`") }
      end
      object_bytes = validate_identity.call(
        object_identity,
        "Founder Knowledge inherited compatibility #{compatibility_type} object", false
      )
      if deep_validation
        object_json = parse_closed_json.call(
          object_bytes,
          "Founder Knowledge inherited compatibility #{compatibility_type} object"
        )
        abort "Founder Knowledge inherited compatibility object schema mismatch" unless
          object_json["schema_version"] == entry["object_schema_version"]
        compatibility_objects[compatibility_type] = object_json
      end
      event_ids_for_entry.each do |event_id|
        event = event_by_id[event_id]
        abort "Founder Knowledge inherited compatibility references an unknown event" unless event
        expected_event_identity = case compatibility_type
                                  when "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL",
                                       "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1"
                                    event["receipt"]
                                  else
                                    event["review"]
                                  end
        abort "Founder Knowledge inherited compatibility object/event binding mismatch" unless
          expected_event_identity == object_identity
      end
      if compatibility_type == "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL"
        event = event_by_id.fetch(event_ids_for_entry.first)
        calculated_event_sha = Digest::SHA256.hexdigest(
          JSON.generate(canonicalize.call(event.reject { |key, _value| key == "event_sha256" }))
        )
        abort "Founder Knowledge inherited event residual hash binding mismatch" unless
          event["status"] == "PENDING_CANDIDATE" &&
          event["event_sha256"] == entry["stored_event_sha256"] &&
          event.dig("receipt", "sha256") == entry["stored_event_sha256"] &&
          calculated_event_sha == entry["calculated_event_sha256"] &&
          entry["stored_event_sha256"].is_a?(String) &&
          entry["stored_event_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
          entry["calculated_event_sha256"].is_a?(String) &&
          entry["calculated_event_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
          entry["stored_event_sha256"] != entry["calculated_event_sha256"]
      else
        abort "Founder Knowledge inherited schema compatibility retained event hashes" unless
          entry["stored_event_sha256"].nil? && entry["calculated_event_sha256"].nil?
      end
    end
    compatibility_for_event = lambda do |event_id, compatibility_type|
      compatibility_entries.find do |entry|
        entry["compatibility_type"] == compatibility_type && entry["event_ids"].include?(event_id)
      end
    end

    validate_reference_identity = lambda do |identity, label|
      exact_keys.call(identity, %w[byte_length path sha256], label)
      path = identity["path"]
      abort "#{label} path invalid" unless path.is_a?(String) && !path.empty?
      pathname = Pathname.new(path)
      resolved = if pathname.absolute?
                   abort "#{label} path is not normalized" unless pathname.cleanpath.to_s == path
                   pathname
                 else
                   abort "#{label} relative path is not normalized" unless pathname.cleanpath.to_s == path
                   candidate = repo_root.join(pathname).cleanpath
                   abort "#{label} relative path escapes repository" unless
                     candidate.to_s.start_with?(repo_root.to_s + File::SEPARATOR)
                   candidate
                 end
      abort "#{label} identity values invalid" unless
        identity["byte_length"].is_a?(Integer) && identity["byte_length"] >= 0 &&
        identity["sha256"].is_a?(String) && identity["sha256"].match?(/\A[0-9a-f]{64}\z/)
      next "".b unless deep_validation
      abort "#{label} must be a non-symlink regular file" unless resolved.file? && !resolved.symlink?
      abort "#{label} resolves through a symlink" unless resolved.realpath.to_s == resolved.cleanpath.to_s
      bytes = resolved.binread
      abort "#{label} byte length mismatch" unless bytes.bytesize == identity["byte_length"]
      abort "#{label} SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == identity["sha256"]
      bytes
    end

    validate_git_blob_identity = lambda do |commit, tree, identity, label|
      abort "#{label} commit/tree invalid" unless
        commit.is_a?(String) && commit.match?(/\A[0-9a-f]{40}\z/) &&
        tree.is_a?(String) && tree.match?(/\A[0-9a-f]{40}\z/)
      actual_tree = `git -C #{repo_root.to_s.shellescape} show -s --format=%T #{commit.shellescape} 2>/dev/null`.strip
      abort "#{label} commit/tree mismatch" unless $?.success? && actual_tree == tree
      exact_keys.call(identity, %w[byte_length path sha256], "#{label} identity")
      path = identity["path"]
      abort "#{label} Git path invalid" unless
        path.is_a?(String) && !Pathname.new(path).absolute? && Pathname.new(path).cleanpath.to_s == path
      bytes = `git -C #{repo_root.to_s.shellescape} show #{commit.shellescape}:#{path.shellescape} 2>/dev/null`.b
      abort "#{label} Git blob lookup failed" unless $?.success?
      abort "#{label} byte length mismatch" unless bytes.bytesize == identity["byte_length"]
      abort "#{label} SHA-256 mismatch" unless Digest::SHA256.hexdigest(bytes) == identity["sha256"]
      bytes
    end

    validate_p1_168_terminal_receipt = lambda do |receipt, event|
      exact_keys.call(
        receipt,
        %w[
          candidate canonical_integration claim_boundary classification exact_failure
          fresh_final_reviews normalized_root_cause recorded_at_utc route_id schema_version
          status task_id terminal_effect v5_pre_freeze_gate
        ],
        "#{event["event_id"]} retained terminal receipt"
      )
      abort "#{event["event_id"]} retained terminal receipt root semantics drift" unless
        receipt["schema_version"] == "p1-168-terminal-receipt/v1" &&
        receipt["status"] == "TERMINAL_CANONICAL_MAKE_VERIFY_NON_PASS" &&
        receipt["classification"] ==
          "TERMINAL_POST_INTEGRATION_CANONICAL_VERIFY_NON_PASS_REVERTED_NO_P1_CAPABILITY" &&
        receipt["task_id"] == "AIOS-P1-168_EXACT_RESPONSE_ADMISSION_MATRIX_RECOVERY_AND_GATE" &&
        receipt["route_id"] == "P1_EXACT_P1_165_SNAPSHOT_BOUND_ADMISSION_KERNEL_RECOVERY_AND_STRICT_EXIT_ROUTE_V1" &&
        receipt["recorded_at_utc"].is_a?(String) &&
        receipt["recorded_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/) &&
        receipt["normalized_root_cause"] == "P1168.CANONICAL_VERIFY.ATOMIC_COMMIT_RECEIPT_INVALID" &&
        receipt["claim_boundary"].is_a?(String) && !receipt["claim_boundary"].empty?
      failure = exact_keys.call(
        receipt["exact_failure"],
        %w[
          command exit_status failing_target independent_evaluator_status invocation_count
          message preflight_status reason_code reported_preflight_atomic_receipt_sha256
          reported_preflight_external_effects_all_false reported_preflight_false_accepts
          reported_preflight_gate_envelope_sha256 reported_preflight_matrix_cases
          reported_preflight_provider_requests reported_preflight_secret_reads
          reported_preflight_source_bundle_sha256 stdout_was_observed_directly_not_persisted_as_a_separate_file
          transient_evidence_root_reported_by_process transient_root_exists_after_process
        ],
        "#{event["event_id"]} retained terminal failure"
      )
      abort "#{event["event_id"]} retained terminal failure semantics drift" unless
        failure["command"] == ["make", "-j1", "verify"] &&
        failure["invocation_count"] == 1 && failure["exit_status"] == 2 &&
        failure["failing_target"] == "p1-fail-closed-response-admission-check" &&
        failure["preflight_status"] == "PASS" &&
        failure["independent_evaluator_status"] == "NON_PASS" &&
        failure["reason_code"] == "ATOMIC_COMMIT_RECEIPT_INVALID" &&
        failure["reported_preflight_matrix_cases"] == 99 &&
        failure["reported_preflight_false_accepts"] == 0 &&
        failure["reported_preflight_provider_requests"] == 0 &&
        failure["reported_preflight_secret_reads"] == 0 &&
        failure["reported_preflight_external_effects_all_false"] == true &&
        failure["transient_root_exists_after_process"] == false &&
        failure["stdout_was_observed_directly_not_persisted_as_a_separate_file"] == true
      candidate = exact_keys.call(
        receipt["candidate"],
        %w[accepted commit evidence_tag evidence_tag_object manifest_byte_length manifest_path manifest_sha256 preserved tree],
        "#{event["event_id"]} retained candidate summary"
      )
      abort "#{event["event_id"]} retained candidate summary drift" unless
        candidate["commit"].is_a?(String) && candidate["commit"].match?(/\A[0-9a-f]{40}\z/) &&
        candidate["tree"].is_a?(String) && candidate["tree"].match?(/\A[0-9a-f]{40}\z/) &&
        candidate["manifest_byte_length"].is_a?(Integer) && candidate["manifest_byte_length"].positive? &&
        candidate["manifest_sha256"].is_a?(String) && candidate["manifest_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
        candidate["preserved"] == true && candidate["accepted"] == false
      gate = exact_keys.call(
        receipt["v5_pre_freeze_gate"],
        %w[
          atomic_commit_receipt_sha256 external_effects_all_false false_accepts
          independent_evaluator_status matrix_cases_passed matrix_cases_total
          provider_requests raw_evidence_manifest_sha256 secret_reads wrapper_status
        ],
        "#{event["event_id"]} retained pre-freeze Gate"
      )
      abort "#{event["event_id"]} retained pre-freeze Gate drift" unless
        gate["wrapper_status"] == "PASS" && gate["independent_evaluator_status"] == "PASS" &&
        gate["matrix_cases_passed"] == 99 && gate["matrix_cases_total"] == 99 &&
        gate["false_accepts"] == 0 && gate["provider_requests"] == 0 && gate["secret_reads"] == 0 &&
        gate["external_effects_all_false"] == true
      reviews = exact_keys.call(
        receipt["fresh_final_reviews"], %w[candidate_manifest_sha256 cto quality security],
        "#{event["event_id"]} retained final reviews"
      )
      %w[cto security quality].each do |role|
        row = exact_keys.call(
          reviews[role], %w[byte_length path sha256 target_verdict],
          "#{event["event_id"]} retained #{role} review"
        )
        abort "#{event["event_id"]} retained #{role} verdict drift" unless row["target_verdict"] == "PASS"
        validate_reference_identity.call(
          row.reject { |key, _value| key == "target_verdict" },
          "#{event["event_id"]} retained #{role} review"
        )
      end
      integration = exact_keys.call(
        receipt["canonical_integration"],
        %w[
          integrated_tree integration_commit pre_integration_commit pre_integration_tree
          pre_integration_tree_restored reset_or_clean_used revert_commit revert_strategy
          revert_tree reviewed_integrated_tree_equal reviewed_tree
        ],
        "#{event["event_id"]} retained canonical integration"
      )
      abort "#{event["event_id"]} retained canonical integration drift" unless
        integration["reviewed_integrated_tree_equal"] == true &&
        integration["reviewed_tree"] == integration["integrated_tree"] &&
        integration["pre_integration_tree_restored"] == true &&
        integration["revert_tree"] == integration["pre_integration_tree"] &&
        integration["revert_strategy"] == "NON_DESTRUCTIVE_GIT_REVERT" &&
        integration["reset_or_clean_used"] == false
      effect = exact_keys.call(
        receipt["terminal_effect"],
        %w[
          accepted_capability additional_p1_168_repair_or_rerun_allowed candidate_integrated_as_accepted
          capability_credit next_eligible_action p1_169_entry p1_170_entry p2_status
          strict_p1_completion successor_replacement_normalization_closure_feasibility_or_remediation_chain_allowed
        ],
        "#{event["event_id"]} retained terminal effect"
      )
      abort "#{event["event_id"]} retained terminal effect drift" unless
        effect["candidate_integrated_as_accepted"] == false && effect["accepted_capability"] == false &&
        effect["capability_credit"] == 0 && effect["strict_p1_completion"] == "6_OF_8_75_PERCENT" &&
        effect["p2_status"] == "HOLD_PENDING_STRICT_P1_EXIT" &&
        effect["next_eligible_action"] == "FOUNDER_P1_PHASE_GATE" &&
        effect["additional_p1_168_repair_or_rerun_allowed"] == false &&
        effect["successor_replacement_normalization_closure_feasibility_or_remediation_chain_allowed"] == false
    end

    validate_alternate_v2_review = lambda do |review, event|
      exact_keys.call(
        review,
        %w[
          blocking_findings candidate fact_findings import_authorization inference_findings
          non_blocking_observations reviewed_at_utc reviewer_identity reviewer_independence
          review_inputs review_scope schema_version target_verdict unknown_findings
        ],
        "#{event["event_id"]} alternate Knowledge Review v2"
      )
      abort "#{event["event_id"]} alternate Knowledge Review root drift" unless
        review["schema_version"] == "founder-knowledge-review/v2" &&
        review["target_verdict"] == "PASS" &&
        review["reviewer_identity"].is_a?(String) && !review["reviewer_identity"].strip.empty? &&
        review["reviewer_independence"] == "INDEPENDENT_NON_IMPLEMENTER_NON_VAULT_IMPORTER" &&
        review["reviewed_at_utc"].is_a?(String) &&
        review["reviewed_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/)
      candidate = exact_keys.call(
        review["candidate"], %w[byte_length exact_identity_verified file_type mode path sha256],
        "#{event["event_id"]} alternate Knowledge Review candidate"
      )
      abort "#{event["event_id"]} alternate Knowledge Review candidate drift" unless
        candidate.reject { |key, _value| %w[exact_identity_verified file_type mode].include?(key) } == event["artifact"] &&
        candidate["exact_identity_verified"] == true &&
        candidate["file_type"] == "REGULAR_FILE_NON_SYMLINK" && candidate["mode"] == "0400"
      if deep_validation
        candidate_stat = File.stat(candidate["path"])
        abort "#{event["event_id"]} alternate Knowledge Review candidate mode drift" unless
          format("%04o", candidate_stat.mode & 0o7777) == candidate["mode"]
      end
      scope = exact_keys.call(
        review["review_scope"],
        %w[
          canonical_truth_consistency exact_bytes_import_boundary fact_inference_unknown_separation
          founder_long_term_learning_value p1_165_terminal_receipt_consistency
          p1_168_contract_boundary_consistency p1_progress_and_p2_hold_accuracy
          secret_and_restricted_material_screen unaccepted_seed_claim_boundary
        ],
        "#{event["event_id"]} alternate Knowledge Review scope"
      )
      abort "#{event["event_id"]} alternate Knowledge Review scope drift" unless
        scope.values.all? { |value| value == "PASS" }
      inputs = exact_keys.call(
        review["review_inputs"],
        %w[
          canonical_truth p1_165_terminal_receipt p1_168_contract
          p1_168_founder_packet_identity_only rejected_engineering_bytes_read
          rejected_worktree_read snapshot_payload_read
        ],
        "#{event["event_id"]} alternate Knowledge Review inputs"
      )
      abort "#{event["event_id"]} alternate Knowledge Review read boundary drift" unless
        inputs["canonical_truth"] == "docs/aios/truth/project_state.yaml" &&
        inputs["rejected_engineering_bytes_read"] == false &&
        inputs["rejected_worktree_read"] == false && inputs["snapshot_payload_read"] == false
      validate_reference_identity.call(inputs["p1_165_terminal_receipt"],
                                       "#{event["event_id"]} P1-165 terminal receipt")
      validate_reference_identity.call(inputs["p1_168_contract"],
                                       "#{event["event_id"]} P1-168 Contract")
      validate_reference_identity.call(inputs["p1_168_founder_packet_identity_only"],
                                       "#{event["event_id"]} P1-168 Founder packet")
      %w[fact_findings inference_findings unknown_findings non_blocking_observations].each do |key|
        abort "#{event["event_id"]} alternate Knowledge Review #{key} invalid" unless
          review[key].is_a?(Array) && !review[key].empty? &&
          review[key].all? { |value| value.is_a?(String) && !value.strip.empty? }
      end
      abort "#{event["event_id"]} alternate Knowledge Review blocking findings drift" unless
        review["blocking_findings"] == []
      authorization = exact_keys.call(
        review["import_authorization"],
        %w[
          authorization_scope authorized authorized_byte_length authorized_candidate_path
          authorized_sha256 exact_bytes_only normalization_or_edit_before_import_allowed
        ],
        "#{event["event_id"]} alternate Knowledge Review import authorization"
      )
      abort "#{event["event_id"]} alternate Knowledge Review import authorization drift" unless
        authorization["authorized"] == true &&
        authorization["authorized_candidate_path"] == event.dig("artifact", "path") &&
        authorization["authorized_byte_length"] == event.dig("artifact", "byte_length") &&
        authorization["authorized_sha256"] == event.dig("artifact", "sha256") &&
        authorization["exact_bytes_only"] == true &&
        authorization["normalization_or_edit_before_import_allowed"] == false &&
        authorization["authorization_scope"].is_a?(String) &&
        authorization["authorization_scope"].start_with?("Founder Knowledge Vault learning import only;")
      review
    end

    validate_v1_review = lambda do |review, event|
      exact_keys.call(
        review,
        %w[
          artifact authorization checks knowledge_verdict record_type review_basis review_scope
          reviewed_at_utc reviewer_role schema_version source_event
        ],
        "#{event["event_id"]} Knowledge Review v1"
      )
      abort "#{event["event_id"]} Knowledge Review v1 root drift" unless
        review["schema_version"] == "founder-knowledge-review/v1" &&
        review["record_type"] == "founder_knowledge_independent_review" &&
        review["knowledge_verdict"] == "PASS" && review["artifact"] == event["artifact"] &&
        review["review_scope"] ==
          "EXACT_LEARNING_ARTIFACT_BYTES_AND_ALLOWED_CANONICAL_TRUTH_TERMINAL_RECEIPT_AND_FINAL_REVIEWS_ONLY" &&
        review["reviewer_role"] == "FRESH_INDEPENDENT_FOUNDER_KNOWLEDGE_REVIEWER" &&
        review["reviewed_at_utc"].is_a?(String) &&
        review["reviewed_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/) &&
        event_by_id.key?(review["source_event"])
      authorization = exact_keys.call(
        review["authorization"],
        %w[
          exact_bytes_only review_non_authoritative vault_import_authorized
          vault_import_condition vault_import_must_be_create_once
          vault_import_must_verify_exact_bytes_equality vault_path
        ],
        "#{event["event_id"]} Knowledge Review v1 authorization"
      )
      abort "#{event["event_id"]} Knowledge Review v1 authorization drift" unless
        authorization["exact_bytes_only"] == true &&
        authorization["review_non_authoritative"] == true &&
        authorization["vault_import_authorized"] == true &&
        authorization["vault_import_must_be_create_once"] == true &&
        authorization["vault_import_must_verify_exact_bytes_equality"] == true &&
        authorization["vault_path"] == sync["vault_path"]
      checks = exact_keys.call(
        review["checks"],
        %w[
          ability_or_route_claim_not_fabricated fact_inference_unknown_separation
          founder_long_term_reuse_value no_rejected_engineering_bytes_or_restricted_source_embedded
          no_secret_credential_token_or_authorization_material
          no_truth_evidence_authority_gate_or_capability_impersonation
          p1_178_candidate_and_review_identity p1_and_p2_state_claims terminal_and_truth_identity
        ],
        "#{event["event_id"]} Knowledge Review v1 checks"
      )
      abort "#{event["event_id"]} Knowledge Review v1 checks drift" unless
        checks.values.all? { |value| value.is_a?(String) && value.start_with?("PASS") }
      basis = exact_keys.call(
        review["review_basis"], %w[canonical final_reviews terminal_receipt truth],
        "#{event["event_id"]} Knowledge Review v1 basis"
      )
      canonical = exact_keys.call(basis["canonical"], %w[commit tree],
                                  "#{event["event_id"]} Knowledge Review v1 canonical")
      reviews = exact_keys.call(basis["final_reviews"], %w[cto quality security],
                                "#{event["event_id"]} Knowledge Review v1 final reviews")
      reviews.each do |role, row|
        exact_keys.call(row, %w[byte_length path sha256 target_verdict],
                        "#{event["event_id"]} Knowledge Review v1 #{role} review")
        abort "#{event["event_id"]} Knowledge Review v1 #{role} verdict drift" unless
          row["target_verdict"] == "NON_PASS"
        validate_reference_identity.call(
          row.reject { |key, _value| key == "target_verdict" },
          "#{event["event_id"]} Knowledge Review v1 #{role} review"
        )
      end
      terminal_receipt = exact_keys.call(
        basis["terminal_receipt"], %w[byte_length path sha256 status],
        "#{event["event_id"]} Knowledge Review v1 terminal receipt"
      )
      abort "#{event["event_id"]} Knowledge Review v1 terminal status drift" unless
        terminal_receipt["status"] == "TERMINAL_FINAL_REVIEW_TARGET_NON_PASS"
      validate_reference_identity.call(
        terminal_receipt.reject { |key, _value| key == "status" },
        "#{event["event_id"]} Knowledge Review v1 terminal receipt"
      )
      validate_git_blob_identity.call(
        canonical["commit"], canonical["tree"], basis["truth"],
        "#{event["event_id"]} Knowledge Review v1 historical Truth"
      )
      review
    end

    validate_v1_import_receipt = lambda do |receipt, event, artifact_bytes, import_bytes|
      exact_keys.call(
        receipt,
        %w[
          artifact bytes_equal canonical imported_at record_type review schema_version
          source_event status vault_import
        ],
        "#{event["event_id"]} Knowledge import receipt v1"
      )
      abort "#{event["event_id"]} Knowledge import receipt v1 root drift" unless
        receipt["schema_version"] == "1.0" &&
        receipt["record_type"] == "founder_knowledge_import_receipt" &&
        receipt["status"] == "IMPORTED" && receipt["bytes_equal"] == true &&
        receipt["artifact"] == event["artifact"] &&
        receipt["review"] == event["review"].merge("verdict" => "PASS") &&
        receipt["vault_import"] == event["vault_import"] &&
        receipt["imported_at"].is_a?(String) &&
        receipt["imported_at"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/) &&
        event_by_id.key?(receipt["source_event"]) && artifact_bytes == import_bytes
      canonical = exact_keys.call(
        receipt["canonical"], %w[commit tree truth],
        "#{event["event_id"]} Knowledge import receipt v1 canonical"
      )
      validate_git_blob_identity.call(
        canonical["commit"], canonical["tree"], canonical["truth"],
        "#{event["event_id"]} Knowledge import receipt v1 historical Truth"
      )
      receipt
    end

    validate_knowledge_review = lambda do |review_bytes, event, expected_verdict|
      next unless deep_validation
      review = parse_closed_json.call(review_bytes, "#{event["event_id"]} Knowledge Review")
      if compatibility_for_event.call(event["event_id"], "ALTERNATE_FOUNDER_KNOWLEDGE_REVIEW_V2")
        abort "#{event["event_id"]} alternate Knowledge Review verdict drift" unless expected_verdict == "PASS"
        next validate_alternate_v2_review.call(review, event)
      end
      if compatibility_for_event.call(event["event_id"], "FOUNDER_KNOWLEDGE_REVIEW_V1")
        abort "#{event["event_id"]} Knowledge Review v1 verdict drift" unless expected_verdict == "PASS"
        next validate_v1_review.call(review, event)
      end
      expected_review_keys = %w[
        candidate findings import_authorization reviewed_at_utc reviewer_identity
        reviewer_independence review_scope schema_version target_verdict verified_facts
      ]
      abort "#{event["event_id"]} Knowledge Review is not closed" unless
        review.keys.sort == expected_review_keys.sort
      expected_scope_keys = %w[
        current_canonical_file_consistency domain_scoped_authority_boundary
        exact_bytes_import_boundary fact_inference_unknown_separation
        founder_learning_usefulness secret_and_restricted_source_screen
      ]
      scope_values = review["review_scope"].is_a?(Hash) ? review["review_scope"].values : []
      expected_scope_valid = if expected_verdict == "PASS"
                               scope_values.all? { |value| value == "PASS" }
                             else
                               scope_values.all? { |value| %w[PASS NON_PASS].include?(value) } &&
                                 scope_values.include?("NON_PASS")
                             end
      abort "#{event["event_id"]} Knowledge Review scope is not closed or verdict-consistent" unless
        review["review_scope"].is_a?(Hash) &&
        review["review_scope"].keys.sort == expected_scope_keys.sort &&
        expected_scope_valid
      abort "#{event["event_id"]} Knowledge Review binding mismatch" unless
        review["schema_version"] == "founder-knowledge-review/v2" &&
        review["reviewer_identity"].is_a?(String) &&
        !review["reviewer_identity"].strip.empty? &&
        review["reviewer_independence"] == "INDEPENDENT_NON_IMPLEMENTER" &&
        review["reviewed_at_utc"].is_a?(String) &&
        review["reviewed_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/) &&
        review["target_verdict"] == expected_verdict &&
        review["candidate"] == event["artifact"].merge("exact_identity_verified" => true) &&
        review["findings"].is_a?(Array) &&
        review["verified_facts"].is_a?(Array)
      authorization = review["import_authorization"]
      abort "#{event["event_id"]} Knowledge Review import authorization is not closed" unless
        authorization.is_a?(Hash) &&
        authorization.keys.sort == %w[
          authorized authorized_byte_length authorized_candidate_path authorized_sha256
          authorization_scope exact_bytes_only normalization_or_edit_before_import_allowed
        ].sort
      expected_authorized = expected_verdict == "PASS"
      abort "#{event["event_id"]} Knowledge Review import authorization drift" unless
        authorization["authorized"] == expected_authorized &&
        authorization["authorized_candidate_path"] == event.dig("artifact", "path") &&
        authorization["authorized_sha256"] == event.dig("artifact", "sha256") &&
        authorization["authorized_byte_length"] == event.dig("artifact", "byte_length") &&
        authorization["exact_bytes_only"] == true &&
        authorization["normalization_or_edit_before_import_allowed"] == false &&
        authorization["authorization_scope"] ==
          "Founder Knowledge Vault learning import only; no Truth, Git, Evidence, Task authority, Gate or capability effect."
      review
    end

    expected_event_keys = %w[
      artifact engineering_blocking event_id event_sha256 occurred_at_utc previous_event_sha256
      rationale receipt review source_commit source_tree status trigger_type vault_import
    ]
    events.each_with_index do |event, index|
      event_id = event["event_id"]
      abort "Founder Knowledge sync event is not closed" unless event.is_a?(Hash) &&
        event.keys.sort == expected_event_keys
      abort "Founder Knowledge sync event id invalid" unless
        event_id.is_a?(String) && event_id.match?(/\AFKS-[A-Z0-9-]+\z/)
      expected_previous = index.zero? ? nil : events[index - 1]["event_sha256"]
      abort "Founder Knowledge sync previous-event chain drift" unless
        event["previous_event_sha256"] == expected_previous
      calculated_event_sha = Digest::SHA256.hexdigest(
        JSON.generate(canonicalize.call(event.reject { |key, _value| key == "event_sha256" }))
      )
      event_hash_residual = compatibility_for_event.call(
        event_id, "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL"
      )
      abort "Founder Knowledge sync event hash drift" unless
        event["event_sha256"].is_a?(String) &&
        event["event_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
        (event["event_sha256"] == calculated_event_sha ||
          (event_hash_residual &&
           event["event_sha256"] == event_hash_residual["stored_event_sha256"] &&
           calculated_event_sha == event_hash_residual["calculated_event_sha256"]))
      if index.zero?
        abort "Founder Knowledge genesis event hash drift" unless
          event["event_sha256"] == "5f03a65ee0f7836ec00e4b4d5040efe025c0d9e386839abb18fb2500cfbddf2f"
      end
      abort "Founder Knowledge sync trigger invalid" unless
        event["trigger_type"].is_a?(String) && event["trigger_type"].match?(/\A[A-Z0-9_]+\z/)
      abort "Founder Knowledge sync event time invalid" unless
        event["occurred_at_utc"].is_a?(String) &&
        event["occurred_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/)
      abort "Founder Knowledge sync source commit invalid" unless
        event["source_commit"].is_a?(String) && event["source_commit"].match?(/\A[0-9a-f]{40}\z/)
      abort "Founder Knowledge sync source tree invalid" unless
        event["source_tree"].is_a?(String) && event["source_tree"].match?(/\A[0-9a-f]{40}\z/)
      actual_tree = `git -C #{repo_root.to_s.shellescape} show -s --format=%T #{event["source_commit"].shellescape} 2>/dev/null`.strip
      abort "Founder Knowledge sync source commit/tree mismatch" unless $?.success? && actual_tree == event["source_tree"]
      system("git", "-C", repo_root.to_s, "merge-base", "--is-ancestor", event["source_commit"], "HEAD",
             out: File::NULL, err: File::NULL)
      abort "Founder Knowledge sync source commit is not canonical ancestry" unless $?.success?
      abort "Founder Knowledge sync rationale missing" unless
        event["rationale"].is_a?(String) && !event["rationale"].strip.empty?
      abort "Founder Knowledge sync event may not block engineering" unless event["engineering_blocking"] == false
      status = event["status"]
      abort "Founder Knowledge sync status invalid" unless statuses.include?(status)
      artifact_bytes = validate_identity.call(event["artifact"], "#{event_id} Artifact", status == "PENDING_CANDIDATE" || status == "NO_MATERIAL_KNOWLEDGE_DELTA")
      review_bytes = validate_identity.call(
        event["review"],
        "#{event_id} Review",
        !%w[REVIEWED_PASS_PENDING_IMPORT NON_PASS IMPORTED].include?(status)
      )
      import_bytes = validate_identity.call(event["vault_import"], "#{event_id} Vault import", status != "IMPORTED")
      receipt_bytes = validate_identity.call(event["receipt"], "#{event_id} receipt", status != "IMPORTED")
      validate_p1_168_terminal_receipt.call(
        compatibility_objects.fetch("EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL"), event
      ) if deep_validation && event_hash_residual
      unless event["vault_import"].values.all?(&:nil?)
        vault_root = Pathname.new(sync["vault_path"]).cleanpath
        import_path = Pathname.new(event.dig("vault_import", "path")).cleanpath
        abort "#{event_id} Vault import path escapes configured Vault root" unless
          import_path.to_s.start_with?(vault_root.to_s + File::SEPARATOR)
      end

      if status == "PENDING_CANDIDATE" || status == "NO_MATERIAL_KNOWLEDGE_DELTA"
        pre_candidate_valid =
          event["artifact"].values.all?(&:nil?) && event["review"].values.all?(&:nil?) &&
          event["vault_import"].values.all?(&:nil?) &&
          if event_hash_residual
            !event["receipt"].values.any?(&:nil?) &&
              event["receipt"] == event_hash_residual["object"].reject { |key, _value| key == "file_type" }
          else
            event["receipt"].values.all?(&:nil?)
          end
        abort "#{event_id} pre-candidate state retains downstream identities" unless pre_candidate_valid
      elsif status == "PENDING_REVIEW"
        abort "#{event_id} pending-review state retains downstream identities" unless
          !event["artifact"].values.any?(&:nil?) &&
          event["review"].values.all?(&:nil?) && event["vault_import"].values.all?(&:nil?) &&
          event["receipt"].values.all?(&:nil?)
      elsif status == "REVIEWED_PASS_PENDING_IMPORT"
        abort "#{event_id} reviewed state retains import identities" unless
          !event["artifact"].values.any?(&:nil?) && !event["review"].values.any?(&:nil?) &&
          event["vault_import"].values.all?(&:nil?) && event["receipt"].values.all?(&:nil?)
        validate_knowledge_review.call(review_bytes, event, "PASS")
      elsif status == "OUTDATED"
        abort "#{event_id} outdated state is missing its Artifact or retains import identities" unless
          !event["artifact"].values.any?(&:nil?) &&
          event["vault_import"].values.all?(&:nil?) && event["receipt"].values.all?(&:nil?)
        validate_knowledge_review.call(review_bytes, event, "PASS") unless event["review"].values.all?(&:nil?)
      elsif status == "NON_PASS"
        validate_knowledge_review.call(review_bytes, event, "NON_PASS")
        abort "#{event_id} NON_PASS state may not retain an import" unless
          event["vault_import"].values.all?(&:nil?) && event["receipt"].values.all?(&:nil?)
      elsif status == "IMPORTED"
        abort "#{event_id} imported Artifact bytes differ from Vault bytes" if
          deep_validation && artifact_bytes != import_bytes
        validate_knowledge_review.call(review_bytes, event, "PASS")
        next unless deep_validation
        receipt = parse_closed_json.call(receipt_bytes, "#{event_id} import receipt")
        if compatibility_for_event.call(event_id, "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1")
          validate_v1_import_receipt.call(receipt, event, artifact_bytes, import_bytes)
          next
        end
        expected_receipt_keys = %w[
          artifact event_id exact_bytes_equal recorded_at_utc review schema_version
          source_commit source_tree truth_sha256 truth_snapshot vault_import
        ]
        abort "#{event_id} import receipt is not closed" unless
          receipt.keys.sort == expected_receipt_keys.sort
        abort "#{event_id} import receipt time invalid" unless
          receipt["recorded_at_utc"].is_a?(String) &&
          receipt["recorded_at_utc"].match?(/\A20[0-9]{2}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z\z/)
        abort "#{event_id} import receipt binding mismatch" unless
          receipt["schema_version"] == "founder-knowledge-import-receipt/v1" &&
          receipt["event_id"] == event_id &&
          receipt["source_commit"] == event["source_commit"] &&
          receipt["source_tree"] == event["source_tree"] &&
          receipt["truth_sha256"].is_a?(String) &&
          receipt["truth_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
          receipt["artifact"] == event["artifact"] &&
          receipt["review"] == event["review"].merge("verdict" => "PASS") &&
          receipt["vault_import"] == event["vault_import"] &&
          receipt["exact_bytes_equal"] == true
        truth_snapshot_bytes = validate_identity.call(
          receipt["truth_snapshot"], "#{event_id} pre-import Truth snapshot", false
        )
        abort "#{event_id} receipt Truth SHA-256 is not bound to snapshot bytes" unless
          receipt["truth_sha256"] == Digest::SHA256.hexdigest(truth_snapshot_bytes)
        canonical_truth_at_source = `git -C #{repo_root.to_s.shellescape} show #{event["source_commit"].shellescape}:docs/aios/truth/project_state.yaml 2>/dev/null`.b
        abort "#{event_id} source-commit Truth lookup failed" unless $?.success?
        abort "#{event_id} pre-import Truth snapshot is not the source-commit canonical Truth" unless
          truth_snapshot_bytes == canonical_truth_at_source
      end
    end
  ' "$ROOT_DIR" "$validation_mode" "$truth_path" "$truth_scope" ||
    fail "Founder Knowledge sync state invalid"
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required"

if [[ $# -gt 0 ]]; then
  if [[ $# -eq 2 && "$1" == "--check-founder-knowledge-section" ]]; then
    check_founder_knowledge_section "$2"
    echo "Founder Knowledge System exact section validation passed."
    exit 0
  fi
  if [[ $# -eq 2 && "$1" == "--check-founder-action-handoff-section" ]]; then
    check_founder_action_handoff_section "$2"
    echo "Founder action handoff exact section validation passed."
    exit 0
  fi
  if [[ $# -eq 1 && "$1" == "--check-static-rules" ]]; then
    check_phase_sequence_section "$RULES_PATH"
    check_founder_action_handoff_section "$RULES_PATH"
    check_founder_knowledge_section "$RULES_PATH"
    echo "Strict phase sequence, Founder action handoff, and Founder Knowledge System static validation passed."
    exit 0
  fi
  if [[ $# -eq 5 && "$1" == "--check-phase-predecessor-state" ]]; then
    check_phase_predecessor_activation "$2" "$3" "$4" "$5" "CANONICAL_ONLY"
    echo "Strict phase predecessor state validation passed."
    exit 0
  fi
  if [[ $# -eq 5 && "$1" == "--test-phase-predecessor-fixture" ]]; then
    check_phase_predecessor_activation "$2" "$3" "$4" "$5" "TEST_FIXTURE"
    echo "Strict phase predecessor fixture validation passed."
    exit 0
  fi
  if [[ $# -eq 1 && "$1" == "--check-knowledge-sync-state" ]]; then
    check_founder_knowledge_sync_state DEEP "$TRUTH_PATH" CANONICAL_ONLY
    echo "Founder Knowledge sync state validation passed."
    exit 0
  fi
  if [[ $# -eq 2 && "$1" == "--test-knowledge-sync-fixture" ]]; then
    check_founder_knowledge_sync_state DEEP "$2" TEST_FIXTURE
    echo "Founder Knowledge sync fixture validation passed."
    exit 0
  fi
  fail "unsupported arguments"
fi

required_files=(
  AGENTS.md
  docs/aios/truth/project_state.yaml
  docs/aios/STRATEGIC_CONSTITUTION.md
  docs/aios/MASTER_EXECUTION_PROTOCOL.md
  docs/aios/FOUNDER_DELEGATION_POLICY.md
  docs/aios/EVALUATION_PROTOCOL.md
  scripts/validate-current-task-authority.rb
  scripts/test-current-task-authority.rb
  scripts/validate-founder-delegation-continuity.rb
  scripts/test-founder-delegation-continuity.rb
  scripts/test-phase-delegated-task-authority.rb
)
for relative_path in "${required_files[@]}"; do
  [[ -f "${ROOT_DIR}/${relative_path}" && ! -L "${ROOT_DIR}/${relative_path}" ]] \
    || fail "required current-authority file missing, non-regular, or symlinked: ${relative_path}"
done

boundary_markers=(
  '一个长期 Goal、一个当前 Phase、一条关键路径、一个当前 Task。'
  '继承的旧 SourceLens 工作区只读，不得修改、暂存、stash、reset、clean 或删除。'
  'Task Contract、Truth 与 validator 必须数据驱动'
  'Founder 再授权中断门（强制执行）'
  '普通 Task lifecycle，不得单独触发 Founder'
  'NO_RESERVED_TRIGGER_CONTINUE_PHASE'
  'MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK'
  'Founder / 用户下一步交付（强制执行）'
  'FOUNDER_ACTION_HANDOFF_CHECK'
  '你现在无需操作，我将在现有授权范围内继续执行。'
  'RECOMMENDED_SINGLE_ACTION'
  'COPY_READY_TEXT_OR_EXACT_STEPS'
  'AGENT_CONTINUATION_AFTER_ACTION'
  '不得连续发送只有相同状态、没有可执行下一步的回复'
  'P1 不建设 Supervisor、Root Custody、完整 Trust Runtime、强隔离平台或 Multi-Agent Runtime。'
  '严格阶段顺序与反偏航（强制执行）'
  '固定阶段路线必须按 `P0 → P1 → P2 → … → P12` 顺序执行'
  '失败的是具体实现路径，不是尚未完成的 Phase 目标'
  '`phase_predecessor_check`'
  '/Users/lijunpeng/Documents/AIOS-Founder-Knowledge-Vault'
  '它不是 Truth、Git source of truth、Evidence Store、Task authority/control plane、Gate authority/decision system 或能力证明'
  '独立 Knowledge Reviewer'
  'exact Artifact bytes PASS'
  'FACT`、`INFERENCE`、`UNKNOWN'
  '不得阻断后续工程开发'
  '禁止删除或覆盖任何历史 Artifact'
  'Knowledge 同步采用事件驱动强制触发'
  'founder_knowledge_sync'
  '`PENDING_CANDIDATE`、`PENDING_REVIEW`、`REVIEWED_PASS_PENDING_IMPORT`、`NON_PASS`、`IMPORTED`、`OUTDATED` 或 `NO_MATERIAL_KNOWLEDGE_DELTA`'
  'NO_MATERIAL_KNOWLEDGE_DELTA'
  'sync receipt'
)
for marker in "${boundary_markers[@]}"; do
  grep -Fq -- "$marker" "$RULES_PATH" || fail "required AGENTS boundary marker missing: ${marker}"
done

check_phase_sequence_section "$RULES_PATH"
check_founder_action_handoff_section "$RULES_PATH"
check_founder_knowledge_section "$RULES_PATH"
check_authority_bindings
check_phase_predecessor_activation
check_founder_knowledge_sync_state STRUCTURAL_ONLY "$TRUTH_PATH" CANONICAL_ONLY
ruby "${ROOT_DIR}/scripts/validate-founder-delegation-continuity.rb"
ruby "${ROOT_DIR}/scripts/validate-current-task-authority.rb"

echo "AIOS current governance validation passed (data-driven current authority only)."

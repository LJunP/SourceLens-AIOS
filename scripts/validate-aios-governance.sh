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
  local canonical_sha256='a87ccd7bc66140fe91c7bc1c12d9998ff77d08716e6e74ebd19065d640a601b3'

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
      CANDIDATE_CREATE ENGINEERING_EVIDENCE_CREATE
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
    if resource_action == "STATE_AUDIT"
      abort "state audit target Task does not equal canonical current Task" unless target_task == task_id
    elsif resource_action == "ROUTE_ACTIVATION"
      abort "route activation precheck requires Task NONE" unless task_id == "NONE" && target_task == "NONE"
    elsif resource_action == "TASK_ACTIVATION"
      abort "Task activation requires canonical Task NONE" unless task_id == "NONE"
      planned_ids = Array(truth.dig("current_phase_route", "task_plan")).each_with_object([]) do |item, ids|
        ids << item["task_id"] if item.is_a?(Hash) && item["task_id"]
      end
      abort "Task activation target is not in the exact current route plan" unless planned_ids.include?(target_task)
    else
      abort "Task resource target does not equal the active canonical Task" unless
        task_id != "NONE" && target_task == task_id
      planned_ids = Array(truth.dig("current_phase_route", "task_plan")).each_with_object([]) do |item, ids|
        ids << item["task_id"] if item.is_a?(Hash) && item["task_id"]
      end
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
      if phase_record["status"] != "COMPLETE"
        abort "#{phase_id} incomplete Founder Gate identity must remain null" unless gate == {
          "status" => "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
          "decision_id" => nil,
          "path" => nil,
          "byte_length" => nil,
          "sha256" => nil
        }
        next
      end

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
      abort "P1 ledger must be COMPLETE when all required items are accepted" unless p1["status"] == "COMPLETE"
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
      schema_version trust_model vault_path
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

    validate_knowledge_review = lambda do |review_bytes, event, expected_verdict|
      next unless deep_validation
      review = JSON.parse(review_bytes)
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
      abort "Founder Knowledge sync event hash drift" unless
        event["event_sha256"].is_a?(String) &&
        event["event_sha256"].match?(/\A[0-9a-f]{64}\z/) &&
        event["event_sha256"] == calculated_event_sha
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
      unless event["vault_import"].values.all?(&:nil?)
        vault_root = Pathname.new(sync["vault_path"]).cleanpath
        import_path = Pathname.new(event.dig("vault_import", "path")).cleanpath
        abort "#{event_id} Vault import path escapes configured Vault root" unless
          import_path.to_s.start_with?(vault_root.to_s + File::SEPARATOR)
      end

      if status == "PENDING_CANDIDATE" || status == "NO_MATERIAL_KNOWLEDGE_DELTA"
        abort "#{event_id} pre-candidate state retains downstream identities" unless
          event["artifact"].values.all?(&:nil?) && event["review"].values.all?(&:nil?) &&
          event["vault_import"].values.all?(&:nil?) && event["receipt"].values.all?(&:nil?)
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
        receipt = JSON.parse(receipt_bytes)
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
  if [[ $# -eq 1 && "$1" == "--check-static-rules" ]]; then
    check_phase_sequence_section "$RULES_PATH"
    check_founder_knowledge_section "$RULES_PATH"
    echo "Strict phase sequence and Founder Knowledge System static validation passed."
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
)
for relative_path in "${required_files[@]}"; do
  [[ -f "${ROOT_DIR}/${relative_path}" && ! -L "${ROOT_DIR}/${relative_path}" ]] \
    || fail "required current-authority file missing, non-regular, or symlinked: ${relative_path}"
done

boundary_markers=(
  '一个长期 Goal、一个当前 Phase、一条关键路径、一个当前 Task。'
  '继承的旧 SourceLens 工作区只读，不得修改、暂存、stash、reset、clean 或删除。'
  'Task Contract、Truth 与 validator 必须数据驱动'
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
check_founder_knowledge_section "$RULES_PATH"
check_authority_bindings
check_phase_predecessor_activation
check_founder_knowledge_sync_state STRUCTURAL_ONLY "$TRUTH_PATH" CANONICAL_ONLY
ruby "${ROOT_DIR}/scripts/validate-current-task-authority.rb"

echo "AIOS current governance validation passed (data-driven current authority only)."

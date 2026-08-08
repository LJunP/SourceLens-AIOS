#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "rbconfig"
require "tmpdir"
require "yaml"

SOURCE_REPO = File.expand_path("..", __dir__)
TRUTH_RELATIVE = "docs/aios/truth/project_state.yaml"
TASK_ID = "AIOS-P2-058_DEV_FIRST_GRAPH_CONTEXT_VALUE_BENCHMARK"
ROUTE_ID = "#{TASK_ID}_PHASE_DELEGATED_ROUTE"
CONTRACT_RELATIVE = "docs/aios/tasks/P2-058_DEV_FIRST_GRAPH_CONTEXT_VALUE_BENCHMARK.yaml"
FALSE_EFFECTS = {
  "network" => false,
  "provider" => false,
  "secret" => false,
  "remote" => false,
  "production" => false,
  "public" => false
}.freeze

class PhaseDelegatedAuthorityTestFailure < StandardError; end

module PhaseDelegatedAuthorityTest
  module_function

  def assert(condition, message)
    raise PhaseDelegatedAuthorityTestFailure, message unless condition
  end

  def command(root, *argv, allow_failure: false)
    stdout, stderr, status = Open3.capture3(*argv, chdir: root)
    unless allow_failure || status.success?
      raise PhaseDelegatedAuthorityTestFailure,
            "command failed: #{argv.join(' ')}\n#{stdout}#{stderr}"
    end
    [stdout, stderr, status]
  end

  def truth(repo)
    YAML.safe_load(
      File.binread(File.join(repo, TRUTH_RELATIVE)),
      permitted_classes: [],
      permitted_symbols: [],
      aliases: false
    )
  end

  def write_truth(repo, value)
    alias_free = JSON.parse(JSON.generate(value))
    File.binwrite(File.join(repo, TRUTH_RELATIVE), YAML.dump(alias_free))
  end

  def identity(path, recorded_path: File.realpath(path))
    bytes = File.binread(path)
    {
      "path" => recorded_path,
      "sha256" => Digest::SHA256.hexdigest(bytes),
      "byte_length" => bytes.bytesize
    }
  end

  def commit(repo, message)
    command(repo, "git", "add", "--all")
    command(repo, "git", "commit", "-m", message)
    status = command(repo, "git", "status", "--porcelain=v1").first
    assert(status.empty?, "fixture repository is dirty after commit")
  end

  def restore_delegated_active_anchor(repo)
    commits = command(
      repo, "git", "log", "--reverse", "--format=%H", "--", TRUTH_RELATIVE
    ).first.lines.map(&:strip).reject(&:empty?)
    active = commits.each_with_object([]) do |commit_id, values|
      bytes, _stderr, status = command(
        repo, "git", "show", "#{commit_id}:#{TRUTH_RELATIVE}", allow_failure: true
      )
      next unless status.success?
      begin
        candidate = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
      rescue Psych::BadAlias, Psych::SyntaxError
        next
      end
      route = candidate["current_phase_route"]
      values << candidate if route.is_a?(Hash) && route["route_id"] == ROUTE_ID && route["status"] == "ACTIVE"
    end.last
    assert(active, "delegated active Truth anchor is missing")
    active.fetch("phase_execution_envelope").fetch("task_ledger").each do |entry|
      entry.delete("capacity_source_task_id")
    end
    write_truth(repo, active)
    commit(repo, "test: restore immutable delegated active Truth fixture")
  end

  def head_identity(repo)
    commit = command(repo, "git", "rev-parse", "HEAD").first.strip
    tree = command(repo, "git", "show", "-s", "--format=%T", commit).first.strip
    { "commit" => commit, "tree" => tree }
  end

  def goal_identity(value)
    goal = value.fetch("goal")
    {
      "raw_sha256" => goal.fetch("observed_raw_body_sha256"),
      "raw_byte_length" => goal.fetch("observed_raw_body_byte_length"),
      "canonicalization" => goal.fetch("body_canonicalization"),
      "canonical_sha256" => goal.fetch("observed_body_sha256"),
      "canonical_byte_length" => goal.fetch("observed_body_byte_length")
    }
  end

  def delegation_binding(value)
    route = value.fetch("current_phase_route")
    envelope = value.fetch("phase_execution_envelope")
    event = value.dig("founder_escalation_control", "source_event")
    source_entry = envelope.fetch("task_ledger").find do |entry|
      entry["task_id"] == event["task_id"] && entry["status"] == event["status"]
    end
    assert(source_entry, "fixture lacks exact source terminal ledger entry")
    reservation = envelope.fetch("reserved")
    {
      "policy" => route.fetch("policy"),
      "delegation_amendment" => envelope.dig("authority_basis", "delegation_amendment"),
      "source_decision" => envelope.dig("authority_basis", "source_decision"),
      "source_terminal_event" => {
        "task_id" => event["task_id"],
        "status" => event["status"],
        "outcome_receipt" => source_entry.fetch("outcome_receipt")
      },
      "phase_envelope_snapshot" => {
        "limits" => envelope.fetch("limits"),
        "consumed" => envelope.fetch("consumed"),
        "reserved" => reservation.slice(
          "task_id", "route_id", "status", "capacity_source_task_id", "budget"
        ),
        "remaining" => envelope.fetch("remaining")
      },
      "founder_packet_for_task" => nil
    }
  end

  def roles
    {
      "owner" => "P2 Phase Delegated Master",
      "worker" => "P2 DEV First Context Value Worker",
      "independent_reviewers" => ["P2 CTO Reviewer", "P2 Security Reviewer", "P2 Quality Reviewer"]
    }
  end

  def budget
    {
      "engineering_hours" => 24,
      "calendar_days" => 6,
      "implementation_iterations" => 4,
      "candidates" => 1
    }
  end

  def allowlisted_paths
    [
      "evaluation-harness/harness/p2-dev-first-context-value",
      "evaluation-harness/evaluator/p2-dev-first-context-value",
      "evaluation-harness/reports/p2-dev-first-context-value"
    ]
  end

  def contract(value, status)
    {
      "schema_version" => "1.0",
      "record_type" => "aios_phase_delegated_independent_task_contract",
      "task_id" => TASK_ID,
      "phase" => "P2",
      "route_id" => ROUTE_ID,
      "status" => status,
      "task_kind" => "REPOSITORY_INTELLIGENCE_CONTEXT_SELECTION_BENCHMARK_RESEARCH",
      "capability" => "REPRODUCIBLE_CONTEXT_BENCHMARK",
      "objective" => "Run one clean-room DEV-first offline graph-context value benchmark without reusing rejected P2 lineage.",
      "capacity_source_task_id" => TASK_ID,
      "budget" => budget,
      "max_same_task_repairs" => 3,
      "roles" => roles,
      "allowlisted_paths" => allowlisted_paths,
      "external_effects" => FALSE_EFFECTS,
      "goal_identity" => goal_identity(value),
      "phase_delegation_binding" => delegation_binding(value),
      "acceptance_criteria" => ["One falsifiable graph-conditioned context comparison is reproducible offline."],
      "required_evidence" => ["Raw run Evidence", "Independent evaluator receipt"],
      "rollback" => "Remove only the owned disposable Task worktree and generated local Evidence.",
      "stop_conditions" => ["Phase capacity is exceeded", "Any external effect is requested"],
      "forbidden_actions" => ["Read or reuse rejected P2 engineering lineage", "Create a Founder packet for this Task"],
      "claim_boundary" => "This Task may establish only an offline P2 graph-to-context value result."
    }
  end

  def write_contract(repo, value, status)
    path = File.join(repo, CONTRACT_RELATIVE)
    FileUtils.mkdir_p(File.dirname(path))
    alias_free = JSON.parse(JSON.generate(contract(value, status)))
    File.binwrite(path, YAML.dump(alias_free))
    identity(path, recorded_path: CONTRACT_RELATIVE)
  end

  def ready_active_work(base, contract_identity)
    active = Marshal.load(Marshal.dump(base.fetch("active_work")))
    active["current_task"] = "NONE"
    active["current_task_status"] = "NONE"
    active["current_task_contract"] = contract_identity
    active["current_task_contract_sha256"] = contract_identity["sha256"]
    active["current_execution_authorization"] = nil
    active["current_execution_authorization_sha256"] = nil
    active["authority_record"] = { "path" => nil, "sha256" => nil, "byte_length" => nil }
    active["execution_nonce"] = nil
    active["execution_nonce_status"] = "NOT_APPLICABLE_TASK_NONE"
    active["authorization_id"] = nil
    active["activation_parent_commit"] = nil
    active["activation_parent_tree"] = nil
    active["task_resource_state"] = "NOT_CREATED_PHASE_DELEGATED_TASK_READY"
    active["task_branch"] = nil
    active["task_worktree"] = nil
    active["execution_evidence_root"] = nil
    active["allowlisted_paths"] = []
    active["budget"] = budget.transform_values { nil }
    active["roles"] = { "owner" => nil, "worker" => nil, "independent_reviewers" => [] }
    active["external_effects"] = FALSE_EFFECTS
    active["offsite_target"] = nil
    active["founder_reserved_authorization"] = nil
    active["founder_reserved_authorization_sha256"] = nil
    active["founder_decision_required"] = false
    active["founder_decision_required_scope"] = nil
    active["escalation_reason"] = nil
    active["user_action_required"] = "NONE"
    active["phase_route_decision_required"] = false
    active["phase_route_user_action_required"] = "NONE"
    active["next_eligible_action"] = "MASTER_ACTIVATE_PHASE_DELEGATED_TASK"
    active
  end

  def make_ready(repo, sandbox)
    value = truth(repo)
    worktree_root = File.join(sandbox, "worktrees")
    evidence_root = File.join(sandbox, "audit")
    FileUtils.mkdir_p(worktree_root)
    FileUtils.mkdir_p(evidence_root)
    value["project"]["canonical_repository"] = File.realpath(repo)
    value["project"]["canonical_branch"] = "main"
    value["project"]["task_worktree_root"] = File.realpath(worktree_root)
    value["project"]["execution_evidence_root_base"] = File.realpath(evidence_root)
    value["project"]["current_route_execution_status"] = "PHASE_DELEGATED_TASK_READY"
    value["goal"]["current_task_authority"] = "NONE"

    task = {
      "task_id" => TASK_ID,
      "status" => "ELIGIBLE_NOT_ACTIVATED",
      "task_kind" => "REPOSITORY_INTELLIGENCE_CONTEXT_SELECTION_BENCHMARK_RESEARCH",
      "capability" => "REPRODUCIBLE_CONTEXT_BENCHMARK",
      "objective" => "Run one clean-room DEV-first offline graph-context value benchmark without reusing rejected P2 lineage.",
      "capacity_source_task_id" => TASK_ID,
      "budget" => budget,
      "max_same_task_repairs" => 3,
      "contract" => nil,
      "independence" => {
        "new_task_id" => true,
        "new_execution_nonce" => true,
        "new_branch" => true,
        "new_worktree" => true,
        "new_contract" => true,
        "new_evidence_root" => true,
        "rejected_lineage_read" => false,
        "rejected_lineage_compare" => false,
        "rejected_lineage_copy" => false,
        "same_phase_objective" => true,
        "successor_or_replacement" => false
      }
    }
    value["current_phase_route"] = {
      "schema_version" => "phase-delegated-independent-task/v1",
      "route_id" => ROUTE_ID,
      "status" => "AUTHORIZED_READY",
      "execution_status" => "PHASE_DELEGATED_TASK_READY",
      "scheduling_status" => "READY_FOR_MASTER_ACTIVATION",
      "phase" => "P2",
      "phase_entry_status" => "AUTHORIZED",
      "policy" => value.dig("authority", "founder_delegation_policy").slice("path", "version", "sha256"),
      "founder_phase_route_decision_required" => false,
      "next_eligible_action" => "MASTER_ACTIVATE_PHASE_DELEGATED_TASK",
      "phase_execution_envelope_ref" => "phase_execution_envelope",
      "source_authority_route_ref" => "historical_p2_058_founder_expansion_phase_route",
      "preceding_terminal_route_ref" => "historical_p2_057_phase_route",
      "selected_task" => task,
      "external_effects" => FALSE_EFFECTS,
      "additional_write_roots" => [],
      "inherited_worktree_inventory_source" => "historical_p2_057_phase_route"
    }
    envelope = value.fetch("phase_execution_envelope")
    envelope["status"] = "TASK_CAPACITY_RESERVED"
    envelope["reserved"] = {
      "task_id" => TASK_ID,
      "route_id" => ROUTE_ID,
      "status" => "ELIGIBLE_NOT_ACTIVATED",
      "capacity_source_task_id" => TASK_ID,
      "budget" => { "engineering_tasks" => 1, "engineering_hours" => 24, "calendar_days" => 6 },
      "contract" => nil,
      "authority" => nil
    }
    envelope["remaining"] = { "engineering_tasks" => 0, "engineering_hours" => 0, "calendar_days" => 0 }
    contract_identity = write_contract(repo, value, "ELIGIBLE_NOT_ACTIVATED")
    task["contract"] = contract_identity
    envelope["reserved"]["contract"] = contract_identity
    value["active_work"] = ready_active_work(value, contract_identity)
    write_truth(repo, value)
    commit(repo, "test: phase-delegated Task READY")
    {
      "repo" => repo,
      "sandbox" => sandbox,
      "worktree_root" => worktree_root,
      "evidence_root" => evidence_root,
      "ready_identity" => head_identity(repo)
    }
  end

  def make_active(fixture)
    repo = fixture.fetch("repo")
    value = truth(repo)
    task = value.dig("current_phase_route", "selected_task")
    task["status"] = "ACTIVE"
    route = value.fetch("current_phase_route")
    route["status"] = "ACTIVE"
    route["execution_status"] = "ACTIVE"
    route["scheduling_status"] = "ACTIVE_PHASE_DELEGATED_TASK"
    route["next_eligible_action"] = "COMPLETE_CURRENT_TASK_GATE"
    value["project"]["current_route_execution_status"] = "ACTIVE_PHASE_DELEGATED_TASK"
    value["goal"]["current_task_authority"] = TASK_ID
    value.dig("phase_execution_envelope", "reserved")["status"] = "ACTIVE"

    contract_identity = write_contract(repo, value, "ACTIVE")
    task["contract"] = contract_identity
    value.dig("phase_execution_envelope", "reserved")["contract"] = contract_identity
    task_branch = "codex/p2-058-dev-first-context-value"
    task_worktree = File.join(fixture.fetch("worktree_root"), "p2-058")
    command(repo, "git", "worktree", "add", "--quiet", "-b", task_branch, task_worktree,
            fixture.dig("ready_identity", "commit"))
    FileUtils.mkdir_p(File.join(fixture.fetch("evidence_root"), "p2-058"))
    evidence = File.realpath(File.join(fixture.fetch("evidence_root"), "p2-058"))
    authorization_id = "PHASE-DELEGATED-P2-058-AUTHORITY-V1"
    nonce = "P2-058-PHASE-DELEGATED-NONCE-V1"
    authority = {
      "schema_version" => "1.0",
      "record_type" => "aios_phase_delegated_independent_task_authority",
      "task_id" => TASK_ID,
      "phase" => "P2",
      "route_id" => ROUTE_ID,
      "status" => "ACTIVE",
      "authorization_id" => authorization_id,
      "task_contract_sha256" => contract_identity["sha256"],
      "execution_nonce" => nonce,
      "activation_parent" => fixture.fetch("ready_identity"),
      "branch" => task_branch,
      "worktree" => File.realpath(task_worktree),
      "evidence_root" => evidence,
      "capacity_source_task_id" => TASK_ID,
      "budget" => budget,
      "max_same_task_repairs" => 3,
      "roles" => roles,
      "allowlisted_paths" => allowlisted_paths,
      "external_effects" => FALSE_EFFECTS,
      "goal_identity" => goal_identity(value),
      "phase_delegation_binding" => delegation_binding(value),
      "founder_reserved_authorization" => nil,
      "founder_reserved_profile" => nil
    }
    authority_path = File.join(fixture.fetch("evidence_root"), "P2_058_PHASE_DELEGATED_AUTHORITY.json")
    File.binwrite(authority_path, JSON.generate(authority))
    authority_identity = identity(authority_path)
    value.dig("phase_execution_envelope", "reserved")["authority"] = authority_identity
    active = value.fetch("active_work")
    active["current_task"] = TASK_ID
    active["current_task_status"] = "ACTIVE"
    active["current_task_contract"] = contract_identity
    active["current_task_contract_sha256"] = contract_identity["sha256"]
    active["current_execution_authorization"] = authority_path
    active["current_execution_authorization_sha256"] = authority_identity["sha256"]
    active["authority_record"] = authority_identity
    active["execution_nonce"] = nonce
    active["execution_nonce_status"] = "ACTIVE"
    active["authorization_id"] = authorization_id
    active["activation_parent_commit"] = fixture.dig("ready_identity", "commit")
    active["activation_parent_tree"] = fixture.dig("ready_identity", "tree")
    active["task_resource_state"] = "ACTIVE_UNIQUE_PHASE_DELEGATED"
    active["task_branch"] = task_branch
    active["task_worktree"] = File.realpath(task_worktree)
    active["execution_evidence_root"] = evidence
    active["allowlisted_paths"] = allowlisted_paths
    active["budget"] = budget
    active["roles"] = roles
    active["external_effects"] = FALSE_EFFECTS
    active["next_eligible_action"] = "COMPLETE_CURRENT_TASK_GATE"
    write_truth(repo, value)
    commit(repo, "test: activate phase-delegated Task without Founder packet")
    fixture.merge(
      "task_branch" => task_branch,
      "task_worktree" => task_worktree,
      "authority_path" => authority_path,
      "active_truth" => value
    )
  end

  def run_authority(repo)
    command(repo, RbConfig.ruby, "scripts/validate-current-task-authority.rb", allow_failure: true)
  end

  def expect_authority(repo, label, state)
    stdout, stderr, status = run_authority(repo)
    assert(status.success?, "#{label} unexpectedly failed\n#{stdout}#{stderr}")
    assert(stdout.include?("CURRENT_TASK_AUTHORITY: PASS state=#{state}"),
           "#{label} returned the wrong state: #{stdout}#{stderr}")
    puts "PASS #{label}"
    1
  end

  def expect_nonpass(repo, label, pattern)
    stdout, stderr, status = run_authority(repo)
    combined = stdout + stderr
    assert(!status.success?, "#{label} unexpectedly passed")
    assert(pattern.match?(combined), "#{label} failed for wrong reason: #{combined}")
    puts "PASS #{label}"
    1
  end

  def expect_safety(repo, label)
    stdout, stderr, status = command(
      repo,
      "bash",
      "scripts/check-p1-safety-boundary.sh",
      "--check-current-p1-route",
      File.join(repo, TRUTH_RELATIVE),
      allow_failure: true
    )
    assert(status.success?, "#{label} unexpectedly failed\n#{stdout}#{stderr}")
    assert(stdout.include?("Current Phase route safety validation passed."),
           "#{label} safety marker missing")
    puts "PASS #{label}"
    1
  end

  def commit_truth(repo, value, message)
    write_truth(repo, value)
    commit(repo, message)
  end

  def run
    assertions = 0
    Dir.mktmpdir("sourcelens-phase-delegated-authority-", "/private/tmp") do |sandbox|
      sandbox_stat = File.lstat(sandbox)
      assert(sandbox_stat.directory? && !sandbox_stat.symlink?, "sandbox is not an owned directory")
      repo = File.join(sandbox, "repo")
      command(sandbox, "git", "clone", "--quiet", "--no-hardlinks", SOURCE_REPO, repo)
      command(repo, "git", "config", "user.email", "phase-delegated-test@local.invalid")
      command(repo, "git", "config", "user.name", "Phase Delegated Authority Test")
      command(repo, "git", "branch", "-M", "main")
      restore_delegated_active_anchor(repo)
      fixture = make_ready(repo, sandbox)
      assertions += expect_authority(repo, "phase-delegated READY full authority", "READY_NONE")
      assertions += expect_safety(repo, "phase-delegated READY full safety")

      fixture = make_active(fixture)
      assertions += expect_authority(repo, "phase-delegated ACTIVE full authority", "ACTIVE_TASK")
      assertions += expect_safety(repo, "phase-delegated ACTIVE full safety")

      original_authority = File.binread(fixture.fetch("authority_path"))
      File.binwrite(fixture.fetch("authority_path"), original_authority + "\n")
      assertions += expect_nonpass(repo, "phase-delegated authority mutation", /byte length mismatch|SHA-256 mismatch/)
      File.binwrite(fixture.fetch("authority_path"), original_authority)
      assertions += expect_authority(repo, "phase-delegated authority mutation restored", "ACTIVE_TASK")

      active_truth = fixture.fetch("active_truth")
      mutated = Marshal.load(Marshal.dump(active_truth))
      fake_task_id = "AIOS-P2-058_FAKE_DELEGATED_TERMINAL"
      fake_route_id = "#{fake_task_id}_PHASE_DELEGATED_ROUTE"
      fake_status = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
      fake_contract_relative = "docs/aios/tasks/P2-058_FAKE_DELEGATED_TERMINAL.yaml"
      fake_contract_path = File.join(repo, fake_contract_relative)
      File.binwrite(
        fake_contract_path,
        YAML.dump(
          {
            "task_id" => fake_task_id,
            "phase" => "P2",
            "route_id" => fake_route_id,
            "status" => fake_status,
            "budget" => {"engineering_hours" => 14, "calendar_days" => 4}
          }
        )
      )
      fake_receipt_path = File.join(fixture.fetch("evidence_root"), "P2_058_FAKE_TERMINAL.json")
      File.binwrite(
        fake_receipt_path,
        JSON.generate({"task_id" => fake_task_id, "route_id" => fake_route_id, "status" => fake_status})
      )
      mutated.dig("phase_execution_envelope", "task_ledger") << {
        "task_id" => fake_task_id,
        "route_id" => fake_route_id,
        "status" => fake_status,
        "budget" => {"engineering_tasks" => 1, "engineering_hours" => 14, "calendar_days" => 4},
        "contract" => identity(fake_contract_path, recorded_path: fake_contract_relative),
        "outcome_receipt" => identity(fake_receipt_path)
      }
      commit_truth(repo, mutated, "test: self-report delegated terminal ledger entry")
      assertions += expect_nonpass(repo, "phase-delegated terminal ledger self-report",
                                   /ledger only accepts anchored source Route consumed Tasks/)
      FileUtils.rm_f(fake_contract_path)
      commit_truth(repo, active_truth, "test: restore anchored source-only ledger")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.dig("current_phase_route", "selected_task", "budget")["implementation_iterations"] = 999
      commit_truth(repo, mutated, "test: attempt phase-delegated implementation iteration expansion")
      assertions += expect_nonpass(repo, "phase-delegated implementation iteration expansion",
                                   /source capacity slot/)
      commit_truth(repo, active_truth, "test: restore phase-delegated implementation iterations")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.dig("current_phase_route", "selected_task", "budget")["implementation_iterations"] = 1
      commit_truth(repo, mutated, "test: attempt impossible repair accounting")
      assertions += expect_nonpass(repo, "phase-delegated repair accounting conservation",
                                   /implementation iterations minus one/)
      commit_truth(repo, active_truth, "test: restore phase-delegated repair accounting")

      mutated = Marshal.load(Marshal.dump(active_truth))
      consumed_source_id = "AIOS-P2-055_ATTESTED_RAW_COMPILER_OBSERVATION_CLOSED_EDGE_GRAPH_KERNEL"
      mutated.dig("current_phase_route", "selected_task")["capacity_source_task_id"] = consumed_source_id
      mutated.dig("phase_execution_envelope", "reserved")["capacity_source_task_id"] = consumed_source_id
      commit_truth(repo, mutated, "test: attempt reuse of consumed source capacity slot")
      assertions += expect_nonpass(repo, "phase-delegated consumed capacity source reuse",
                                   /capacity source is already consumed|reuses consumed source capacity/)
      commit_truth(repo, active_truth, "test: restore unused source capacity slot")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.dig("phase_execution_envelope", "reserved")["authority"] =
        Marshal.load(Marshal.dump(mutated.dig("active_work", "current_task_contract")))
      commit_truth(repo, mutated, "test: drift reserved authority identity")
      assertions += expect_nonpass(repo, "phase-delegated reserved authority drift",
                                   /reserved authority identity drift|does not equal active authority/)
      commit_truth(repo, active_truth, "test: restore reserved authority identity")

      authority_hardlink = "#{fixture.fetch("authority_path")}.hardlink"
      File.link(fixture.fetch("authority_path"), authority_hardlink)
      mutated = Marshal.load(Marshal.dump(active_truth))
      hardlink_identity = identity(authority_hardlink)
      mutated.dig("phase_execution_envelope", "reserved")["authority"] = hardlink_identity
      mutated["active_work"]["authority_record"] = hardlink_identity
      mutated["active_work"]["current_execution_authorization"] = authority_hardlink
      mutated["active_work"]["current_execution_authorization_sha256"] = hardlink_identity["sha256"]
      commit_truth(repo, mutated, "test: substitute hardlink alias for delegated authority")
      assertions += expect_nonpass(repo, "phase-delegated authority hardlink alias",
                                   /must not be hardlinked/)
      File.unlink(authority_hardlink)
      commit_truth(repo, active_truth, "test: restore single-link delegated authority")

      contract_path = File.join(repo, CONTRACT_RELATIVE)
      contract_hardlink_source = File.join(sandbox, "contract-hardlink-source.yaml")
      FileUtils.cp(contract_path, contract_hardlink_source)
      File.unlink(contract_path)
      File.link(contract_hardlink_source, contract_path)
      assertions += expect_nonpass(repo, "phase-delegated Contract hardlink alias",
                                   /must not be hardlinked/)
      File.unlink(contract_path)
      File.rename(contract_hardlink_source, contract_path)
      assertions += expect_authority(repo, "phase-delegated ACTIVE after hardlink cleanup", "ACTIVE_TASK")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.delete("phase_execution_envelope")
      mutated["current_phase_route"]["schema_version"] = "1.1"
      commit_truth(repo, mutated, "test: delete phase envelope and escape through generic Route")
      assertions += expect_nonpass(repo, "phase-delegated envelope deletion escape",
                                   /active Phase delegation requires a phase execution envelope/)
      commit_truth(repo, active_truth, "test: restore phase-delegated envelope")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated["current_phase_route"]["external_effects"]["network"] = true
      commit_truth(repo, mutated, "test: attempt phase-delegated effect expansion")
      assertions += expect_nonpass(repo, "phase-delegated effect expansion", /may not expand effects/)
      commit_truth(repo, active_truth, "test: restore phase-delegated effects")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.dig("current_phase_route", "selected_task", "budget")["engineering_hours"] = 15
      mutated.dig("phase_execution_envelope", "reserved", "budget")["engineering_hours"] = 15
      commit_truth(repo, mutated, "test: attempt phase-delegated budget oversubscription")
      assertions += expect_nonpass(repo, "phase-delegated budget oversubscription", /remaining accounting drift/)
      commit_truth(repo, active_truth, "test: restore phase-delegated budget")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.dig("phase_execution_envelope", "authority_basis", "source_decision")["sha256"] = "0" * 64
      commit_truth(repo, mutated, "test: drift phase source Decision")
      assertions += expect_nonpass(repo, "phase-delegated source Decision drift", /source Decision identity drift/)
      commit_truth(repo, active_truth, "test: restore phase source Decision")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated["active_work"]["founder_reserved_authorization"] =
        mutated.dig("historical_p2_055_phase_route", "original_founder_packet", "path")
      mutated["active_work"]["founder_reserved_authorization_sha256"] =
        mutated.dig("historical_p2_055_phase_route", "original_founder_packet", "sha256")
      commit_truth(repo, mutated, "test: inject routine Founder packet")
      assertions += expect_nonpass(repo, "phase-delegated routine Founder packet rejected",
                                   /must not invent a Founder authorization or action/)
      commit_truth(repo, active_truth, "test: remove routine Founder packet")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated.dig("current_phase_route", "selected_task")["task_id"] =
        "AIOS-P2-055_ATTESTED_RAW_COMPILER_OBSERVATION_CLOSED_EDGE_GRAPH_KERNEL"
      mutated["current_phase_route"]["route_id"] =
        "AIOS-P2-055_ATTESTED_RAW_COMPILER_OBSERVATION_CLOSED_EDGE_GRAPH_KERNEL_PHASE_DELEGATED_ROUTE"
      mutated.dig("phase_execution_envelope", "reserved")["task_id"] =
        mutated.dig("current_phase_route", "selected_task", "task_id")
      mutated.dig("phase_execution_envelope", "reserved")["route_id"] =
        mutated.dig("current_phase_route", "route_id")
      commit_truth(repo, mutated, "test: reuse rejected historical Task id")
      assertions += expect_nonpass(repo, "phase-delegated rejected Task id reuse", /reuses a historical Task id/)
      commit_truth(repo, active_truth, "test: restore independent Task identity")

      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated["historical_p2_057_previous_phase_route"] = {
        "selected_task" => {"task_id" => TASK_ID}
      }
      commit_truth(repo, mutated, "test: reuse historical selected Task id")
      assertions += expect_nonpass(repo, "phase-delegated historical selected Task id reuse",
                                   /reuses a historical Task id/)
      commit_truth(repo, active_truth, "test: restore historical selected Task isolation")

      alias_path = File.join(fixture.fetch("worktree_root"), "p2-057-alias")
      File.symlink(fixture.fetch("task_worktree"), alias_path)
      mutated = Marshal.load(Marshal.dump(active_truth))
      mutated["active_work"]["task_worktree"] = alias_path
      commit_truth(repo, mutated, "test: use symlink alias for delegated worktree")
      assertions += expect_nonpass(repo, "phase-delegated worktree symlink alias",
                                   /non-symlink directories|symlinked components/)
      commit_truth(repo, active_truth, "test: restore physical delegated worktree")
      File.unlink(alias_path)

      historical = active_truth.fetch("historical_p2_055_terminal_active_work")
      lineage_cases = {
        "execution_nonce" => ["execution_nonce"],
        "authorization_id" => ["authorization_id"],
        "task_branch" => ["task_branch"],
        "task_worktree" => ["task_worktree"],
        "execution_evidence_root" => ["execution_evidence_root"],
        "current_task_contract" => ["current_task_contract"],
        "authority_record" => ["authority_record"]
      }
      lineage_cases.each do |label, keys|
        mutated = Marshal.load(Marshal.dump(active_truth))
        mutated_historical = mutated.fetch("historical_p2_055_terminal_active_work")
        current = mutated.fetch("active_work")
        mutated_historical[keys.first] = Marshal.load(Marshal.dump(current[keys.first]))
        commit_truth(repo, mutated, "test: reuse historical #{label}")
        assertions += expect_nonpass(repo, "phase-delegated historical #{label} reuse",
                                     /reuses historical execution lineage identity|historical physical worktree|Evidence overlaps historical execution lineage/)
        commit_truth(repo, active_truth, "test: restore historical #{label} isolation")
      end

      extra_worktree = File.join(fixture.fetch("worktree_root"), "extra")
      command(repo, "git", "worktree", "add", "--quiet", "-b", "codex/p2-extra-unbound", extra_worktree, "HEAD")
      assertions += expect_nonpass(repo, "phase-delegated extra worktree", /Git worktree set does not equal/)
      command(repo, "git", "worktree", "remove", "--force", extra_worktree)
      command(repo, "git", "branch", "-D", "codex/p2-extra-unbound")
      assertions += expect_authority(repo, "phase-delegated ACTIVE after worktree cleanup", "ACTIVE_TASK")

      command(repo, "git", "worktree", "remove", "--force", fixture.fetch("task_worktree"))
      command(repo, "git", "branch", "-D", fixture.fetch("task_branch"))
    end
    puts "PHASE_DELEGATED_TASK_AUTHORITY_TESTS: PASS assertions=#{assertions}"
  end
end

begin
  PhaseDelegatedAuthorityTest.run
  exit 0
rescue PhaseDelegatedAuthorityTestFailure => e
  warn "PHASE_DELEGATED_TASK_AUTHORITY_TESTS: NON_PASS #{e.message}"
  exit 1
rescue StandardError => e
  warn "PHASE_DELEGATED_TASK_AUTHORITY_TESTS: NON_PASS unexpected #{e.class}: #{e.message}"
  warn e.backtrace.first(8).join("\n")
  exit 1
end

#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "open3"
require "pathname"
require "rbconfig"
require "tmpdir"
require "yaml"

VALIDATOR = File.expand_path("validate-current-task-authority.rb", __dir__)
SAFETY_VALIDATOR = File.expand_path("check-p1-safety-boundary.sh", __dir__)
SOURCE_REPO = File.expand_path("..", __dir__)
TRUTH_RELATIVE = "docs/aios/truth/project_state.yaml"
POLICY_RELATIVE = "docs/aios/FOUNDER_DELEGATION_POLICY.md"

class TestFailure < StandardError; end

class CurrentTaskAuthorityTest
  def initialize
    @owned = {}
    @passes = 0
  end

  def assert(condition, message)
    raise TestFailure, message unless condition
  end

  def shell(root, *argv)
    stdout, stderr, status = Open3.capture3(*argv, chdir: root)
    raise TestFailure, "command failed: #{argv.join(' ')}\n#{stdout}#{stderr}" unless status.success?
    stdout
  end

  def register_owned(path)
    stat = File.lstat(path)
    @owned[path] = [stat.dev, stat.ino]
    path
  end

  def assert_owned(path)
    expected = @owned[path]
    raise TestFailure, "unowned fixture path: #{path}" unless expected
    stat = File.lstat(path)
    raise TestFailure, "fixture became a symlink: #{path}" if stat.symlink?
    raise TestFailure, "fixture identity changed: #{path}" unless [stat.dev, stat.ino] == expected
    stat
  end

  def create_exclusive(path, bytes)
    FileUtils.mkdir_p(File.dirname(path))
    flags = File::WRONLY | File::CREAT | File::EXCL
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags, 0o600) do |file|
      file.write(bytes)
      file.flush
      file.fsync
    end
    register_owned(path)
  end

  def rewrite_owned(path, bytes)
    expected = assert_owned(path)
    flags = File::WRONLY | File::TRUNC
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [expected.dev, expected.ino], "fixture changed while opening")
      file.write(bytes)
      file.flush
      file.fsync
    end
  end

  def tamper_owned_byte(path)
    expected = assert_owned(path)
    flags = File::RDWR
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    original = nil
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [expected.dev, expected.ino], "fixture changed while opening")
      original = file.read(1)
      assert(original && !original.empty?, "cannot tamper empty fixture")
      file.seek(0, IO::SEEK_SET)
      file.write((original.getbyte(0) ^ 1).chr)
      file.flush
      file.fsync
    end
    original
  end

  def restore_owned_byte(path, original)
    expected = assert_owned(path)
    flags = File::RDWR
    flags |= File::NOFOLLOW if defined?(File::NOFOLLOW)
    File.open(path, flags) do |file|
      opened = file.stat
      assert([opened.dev, opened.ino] == [expected.dev, expected.ino], "fixture changed while restoring")
      file.seek(0, IO::SEEK_SET)
      file.write(original)
      file.flush
      file.fsync
    end
  end

  def verified_source_copy(source, destination, sha, length)
    stat = File.lstat(source)
    assert(stat.file? && !stat.symlink?, "source identity fixture is not a regular file")
    bytes = File.binread(source)
    assert(bytes.bytesize == length, "source identity byte length mismatch")
    assert(Digest::SHA256.hexdigest(bytes) == sha, "source identity SHA mismatch")
    create_exclusive(destination, bytes)
    destination
  end

  def commit(repo, message)
    shell(repo, "git", "add", "--all")
    shell(repo, "git", "commit", "-m", message)
    shell(repo, "git", "status", "--porcelain=v1").tap do |status|
      assert(status.empty?, "fixture repository is not clean after commit")
    end
  end

  def run_validator(repo)
    Open3.capture3(RbConfig.ruby, VALIDATOR, chdir: repo)
  end

  def run_safety(repo, truth_path)
    Open3.capture3("bash", SAFETY_VALIDATOR, "--check-current-p1-route", truth_path, chdir: repo)
  end

  def expect_pass(repo, label)
    stdout, stderr, status = run_validator(repo)
    assert(status.success?, "#{label}: expected PASS\n#{stdout}#{stderr}")
    assert(stdout.include?("CURRENT_TASK_AUTHORITY: PASS"), "#{label}: PASS marker missing")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_nonpass(repo, label, pattern)
    stdout, stderr, status = run_validator(repo)
    output = stdout + stderr
    assert(!status.success?, "#{label}: expected NON_PASS")
    assert(output.include?("CURRENT_TASK_AUTHORITY: NON_PASS"), "#{label}: NON_PASS marker missing")
    assert(pattern.match?(output), "#{label}: expected #{pattern.inspect}, got #{output.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_safety_pass(repo, truth_path, label)
    stdout, stderr, status = run_safety(repo, truth_path)
    assert(status.success?, "#{label}: expected safety PASS\n#{stdout}#{stderr}")
    assert(stdout.include?("Current P1 route safety validation passed."), "#{label}: safety PASS marker missing")
    @passes += 1
    puts "PASS #{label}"
  end

  def expect_safety_nonpass(repo, truth_path, label, pattern)
    stdout, stderr, status = run_safety(repo, truth_path)
    output = stdout + stderr
    assert(!status.success?, "#{label}: expected safety NON_PASS")
    assert(pattern.match?(output), "#{label}: expected #{pattern.inspect}, got #{output.inspect}")
    @passes += 1
    puts "PASS #{label}"
  end

  def yaml(path)
    YAML.safe_load(File.binread(path), permitted_classes: [], permitted_symbols: [], aliases: false)
  end

  def dump_owned_yaml(path, value)
    rewrite_owned(path, YAML.dump(value))
  end

  def ready_active_work
    {
      "current_task" => "NONE",
      "current_task_status" => "NONE",
      "current_task_contract" => { "path" => nil, "sha256" => nil, "byte_length" => nil },
      "current_task_contract_sha256" => nil,
      "current_execution_authorization" => nil,
      "current_execution_authorization_sha256" => nil,
      "authority_record" => { "path" => nil, "sha256" => nil, "byte_length" => nil },
      "execution_nonce" => nil,
      "execution_nonce_status" => "NOT_APPLICABLE_TASK_NONE",
      "authorization_id" => nil,
      "activation_parent_commit" => nil,
      "activation_parent_tree" => nil,
      "task_resource_state" => "NOT_CREATED_ROUTE_READY",
      "task_branch" => nil,
      "task_worktree" => nil,
      "execution_evidence_root" => nil,
      "allowlisted_paths" => [],
      "budget" => {
        "engineering_hours" => nil,
        "calendar_days" => nil,
        "implementation_iterations" => nil,
        "candidates" => nil
      },
      "roles" => { "owner" => nil, "worker" => nil, "independent_reviewers" => [] },
      "external_effects" => false_effects,
      "offsite_target" => nil,
      "founder_reserved_authorization" => nil,
      "founder_reserved_authorization_sha256" => nil,
      "founder_decision_required" => false,
      "escalation_reason" => nil,
      "user_action_required" => "NONE",
      "next_eligible_action" => "MASTER_ACTIVATE_FIRST_TASK"
    }
  end

  def false_effects
    {
      "network" => false,
      "provider" => false,
      "secret" => false,
      "remote" => false,
      "production" => false,
      "public" => false
    }
  end

  def deep_copy(value)
    Marshal.load(Marshal.dump(value))
  end

  def prepare_fixture(sandbox)
    source_truth_path = File.join(SOURCE_REPO, TRUTH_RELATIVE)
    source_truth = yaml(source_truth_path)
    source_head = shell(SOURCE_REPO, "git", "rev-parse", "HEAD").strip
    repo = File.join(sandbox, "repo")
    external = File.join(sandbox, "external")
    FileUtils.mkdir_p(external)
    shell(sandbox, "git", "clone", "--quiet", "--no-hardlinks", SOURCE_REPO, repo)
    shell(repo, "git", "config", "user.name", "Authority Fixture")
    shell(repo, "git", "config", "user.email", "authority-fixture@example.invalid")
    shell(repo, "git", "checkout", "--quiet", "-B", "main", source_head)

    truth_path = File.join(repo, TRUTH_RELATIVE)
    policy_path = File.join(repo, POLICY_RELATIVE)
    register_owned(truth_path)
    register_owned(policy_path)
    rewrite_owned(policy_path, File.binread(File.join(SOURCE_REPO, POLICY_RELATIVE)))

    packet_identity = source_truth.fetch("current_phase_route").fetch("decision_packet")
    packet_source = packet_identity.fetch("path")
    goal_source = source_truth.fetch("goal").fetch("source_attachment_path")
    packet_path = verified_source_copy(
      packet_source,
      File.join(external, "decision-packet.md"),
      packet_identity.fetch("sha256"),
      packet_identity.fetch("byte_length")
    )
    goal_path = verified_source_copy(
      goal_source,
      File.join(external, "goal.txt"),
      "28bc384fbac9d69c6de3ef8709a5be5a0473309b0fe0e54b01bead13d4fa9cf1",
      19_433
    )

    worktree_root = File.join(external, "worktrees")
    evidence_base = File.join(external, "audit")
    FileUtils.mkdir_p(worktree_root)
    FileUtils.mkdir_p(evidence_base)

    truth = source_truth
    truth["goal"]["source_attachment_path"] = goal_path
    truth["goal"]["current_task_authority"] = "NONE"
    truth["project"]["canonical_repository"] = repo
    truth["project"]["canonical_branch"] = "main"
    truth["project"]["task_worktree_root"] = worktree_root
    truth["project"]["execution_evidence_root_base"] = evidence_base
    truth["project"]["phase_execution_status"] = "AUTHORIZED_READY"
    truth["project"]["p1_execution_status"] = "AUTHORIZED_READY"
    truth["current_phase_route"]["status"] = "AUTHORIZED_READY"
    truth["current_phase_route"]["decision_packet"]["path"] = packet_path
    first_task_id = truth.fetch("current_phase_route").fetch("first_task").fetch("task_id")
    truth.fetch("task_history").delete_if do |_key, record|
      record.is_a?(Hash) && record["task_id"] == first_task_id
    end
    truth["current_phase_route"]["first_task"]["status"] = "ELIGIBLE_NOT_ACTIVATED"
    truth["current_phase_route"]["next_eligible_action"] = "MASTER_ACTIVATE_FIRST_TASK"
    truth["current_phase_route"]["inherited_worktree_inventory"] = []
    truth["current_phase_route"].delete("active_task")
    truth["active_work"] = ready_active_work
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: fixture ready route")

    {
      "repo" => repo,
      "external" => external,
      "truth_path" => truth_path,
      "policy_path" => policy_path,
      "packet_path" => packet_path,
      "goal_path" => goal_path,
      "worktree_root" => worktree_root,
      "evidence_base" => evidence_base
    }
  end

  def ready_tests(fixture)
    repo = fixture["repo"]
    expect_pass(repo, "ready route with Task NONE")
    expect_safety_pass(repo, fixture["truth_path"], "ready route safety with Task NONE")

    original = tamper_owned_byte(fixture["packet_path"])
    expect_nonpass(repo, "decision packet byte tamper", /decision packet.*SHA-256 mismatch/i)
    restore_owned_byte(fixture["packet_path"], original)
    expect_pass(repo, "decision packet restored")

    original = tamper_owned_byte(fixture["goal_path"])
    expect_nonpass(repo, "Goal source byte tamper", /Goal raw SHA-256 mismatch/)
    restore_owned_byte(fixture["goal_path"], original)

    original = tamper_owned_byte(fixture["policy_path"])
    commit(repo, "test: tamper owned authority policy bytes")
    expect_nonpass(repo, "authority policy byte tamper", /founder_delegation_policy SHA-256 mismatch/)
    restore_owned_byte(fixture["policy_path"], original)
    commit(repo, "test: restore owned authority policy bytes")

    truth = yaml(fixture["truth_path"])
    original_hours = truth["current_phase_route"]["envelope"]["max_engineering_hours"]
    truth["current_phase_route"]["envelope"]["max_engineering_hours"] = original_hours + 1
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: detach route envelope from decision packet")
    expect_nonpass(repo, "route envelope decision-byte detachment", /envelope max_engineering_hours does not match/)
    truth["current_phase_route"]["envelope"]["max_engineering_hours"] = original_hours
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore route envelope binding")

    truth = yaml(fixture["truth_path"])
    if truth["current_phase_route"]["founder_reserved_profile"]
      original_host = truth["current_phase_route"]["founder_reserved_profile"]["transport"]["host"]
      truth["current_phase_route"]["founder_reserved_profile"]["transport"]["host"] = "localhost"
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: expand literal gateway host to DNS name")
      expect_nonpass(repo, "Founder profile host expansion", /transport exceeds the literal local-gateway boundary/)
      expect_safety_nonpass(repo, fixture["truth_path"], "safety rejects Founder profile host expansion",
                            /transport exceeds literal loopback boundary/)
      truth["current_phase_route"]["founder_reserved_profile"]["transport"]["host"] = original_host
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: restore literal gateway host")

      truth = yaml(fixture["truth_path"])
      profile = truth["current_phase_route"]["founder_reserved_profile"]
      call_key = profile["schema_version"] == "2.0" ? "provider_requests_max" : "source_bearing_max"
      original_call_limit = profile["call_limits"][call_key]
      profile["call_limits"][call_key] = original_call_limit + 1
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: expand Founder-reserved call budget")
      expect_nonpass(repo, "Founder profile call expansion", /call limits drifted/)
      profile["call_limits"][call_key] = original_call_limit
      dump_owned_yaml(fixture["truth_path"], truth)
      commit(repo, "test: restore Founder-reserved call budget")
    end

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["envelope"]["external_effects"]["remote"] = true
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: authorize remote effect outside packet")
    expect_nonpass(repo, "remote effect expansion", /exact authorized external-effect map/)
    truth["current_phase_route"]["envelope"]["external_effects"]["remote"] = false
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore remote deny")

    accepted_lineage_tests(fixture)

    truth = yaml(fixture["truth_path"])
    link_path = File.join(fixture["external"], "decision-packet-link.md")
    File.symlink(fixture["packet_path"], link_path)
    link_stat = File.lstat(link_path)
    assert(link_stat.symlink?, "failed to create owned symlink fixture")
    truth["current_phase_route"]["decision_packet"]["path"] = link_path
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: point route packet at symlink")
    expect_nonpass(repo, "decision packet symlink", /must not be a symlink/)
    truth["current_phase_route"]["decision_packet"]["path"] = fixture["packet_path"]
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore real route packet")
    current_link = File.lstat(link_path)
    assert(current_link.symlink? && [current_link.dev, current_link.ino] == [link_stat.dev, link_stat.ino],
           "owned symlink fixture identity changed before cleanup")
    assert(File.readlink(link_path) == fixture["packet_path"], "owned symlink target changed before cleanup")
    File.unlink(link_path)
  end

  def top_level_history_record(truth, task_id)
    matches = truth.fetch("task_history").values.select do |record|
      record.is_a?(Hash) && record["task_id"] == task_id
    end
    assert(matches.length == 1, "fixture accepted input must have one top-level history record")
    matches.first
  end

  def accepted_lineage_tests(fixture)
    repo = fixture["repo"]
    truth_path = fixture["truth_path"]

    truth = yaml(truth_path)
    inputs = truth.fetch("current_phase_route").fetch("accepted_inputs")
    primary_key = inputs.keys.sort.first
    primary = inputs.fetch(primary_key)
    original_status = primary.fetch("status")
    primary["status"] = "MASTER_TASK_GATE_NOT_ACCEPTED_COMPLETE"
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: masquerade rejected accepted-input status")
    expect_nonpass(repo, "rejected-status accepted-input masquerade", /status is not an exact accepted Gate lifecycle/)
    primary["status"] = original_status
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: restore accepted-input status")

    truth = yaml(truth_path)
    inputs = truth.fetch("current_phase_route").fetch("accepted_inputs")
    input_pairs = inputs.keys.sort.combination(2).to_a
    alias_pair = input_pairs.find { |left, right| inputs[left]["task_id"] != inputs[right]["task_id"] }
    assert(alias_pair, "fixture needs two accepted inputs with distinct Task ids")
    alias_source, alias_target = alias_pair
    original_task_id = inputs[alias_source].fetch("task_id")
    inputs[alias_source]["task_id"] = inputs[alias_target].fetch("task_id")
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: alias one accepted input to another Task id")
    expect_nonpass(repo, "accepted-input Task-id alias", /history (?:status|contract|task_contract_sha256|accepted_candidate_)/)
    inputs[alias_source]["task_id"] = original_task_id
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: restore accepted-input Task id")

    truth = yaml(truth_path)
    inputs = truth.fetch("current_phase_route").fetch("accepted_inputs")
    substitution = nil
    inputs.keys.sort.each do |input_key|
      input = inputs.fetch(input_key)
      history = top_level_history_record(truth, input.fetch("task_id"))
      [%w[activation_parent_commit activation_parent_tree], %w[activation_commit activation_tree]].each do |commit_key, tree_key|
        next unless history[commit_key].is_a?(String) && history[tree_key].is_a?(String)
        next if history[commit_key] == input["accepted_candidate_commit"]
        substitution = [input_key, history[commit_key], history[tree_key]]
        break
      end
      break if substitution
    end
    assert(substitution, "fixture needs a pre-acceptance parent candidate for substitution")
    input_key, substitute_commit, substitute_tree = substitution
    input = inputs.fetch(input_key)
    accepted_commit = input.fetch("accepted_candidate_commit")
    accepted_tree = input.fetch("accepted_candidate_tree")
    input["accepted_candidate_commit"] = substitute_commit
    input["accepted_candidate_tree"] = substitute_tree
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: substitute pre-acceptance parent candidate")
    expect_nonpass(repo, "pre-acceptance parent candidate substitution",
                   /history accepted_candidate_commit binding mismatch/)
    input["accepted_candidate_commit"] = accepted_commit
    input["accepted_candidate_tree"] = accepted_tree
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: restore accepted candidate lineage")
    expect_pass(repo, "accepted-input lineage restored")
  end

  def activate_fixture(fixture)
    repo = fixture["repo"]
    truth_path = fixture["truth_path"]
    truth = yaml(truth_path)
    task = truth.fetch("current_phase_route").fetch("first_task")
    task_id = task.fetch("task_id")
    route_id = truth.fetch("current_phase_route").fetch("route_id")
    contract_relative = task.fetch("contract_path")
    contract_path = File.join(repo, contract_relative)
    FileUtils.mkdir_p(File.dirname(contract_path))

    budget = {
      "engineering_hours" => task.fetch("max_engineering_hours"),
      "calendar_days" => task.fetch("max_calendar_days"),
      "implementation_iterations" => task.fetch("max_implementation_iterations"),
      "candidates" => task.fetch("max_candidates")
    }
    roles = {
      "owner" => "Fixture Master",
      "worker" => "Fixture Worker",
      "independent_reviewers" => ["Fixture CTO", "Fixture Security", "Fixture Quality"]
    }
    allowlisted = ["evaluation-harness/harness/local-patch-control/**", "scripts/verify-fixture-task.sh"]
    contract = {
      "schema_version" => 1,
      "record_type" => "aios_phase_local_task_contract",
      "task_id" => task_id,
      "phase" => "P1",
      "route_id" => route_id,
      "status" => "ACTIVE",
      "objective" => "Run one bounded local-gateway finite-IR fixture task.",
      "why_now" => "Exercise the exact Founder-reserved authority path without network in this fixture.",
      "budget" => budget,
      "roles" => roles,
      "allowlisted_paths" => allowlisted,
      "external_effects" => deep_copy(truth.fetch("current_phase_route").fetch("envelope").fetch("external_effects")),
      "founder_reserved_authorization" => {
        "path" => truth.dig("current_phase_route", "decision_packet", "path"),
        "sha256" => truth.dig("current_phase_route", "decision_packet", "sha256"),
        "byte_length" => truth.dig("current_phase_route", "decision_packet", "byte_length"),
        "authorization_token" => truth.dig("current_phase_route", "authorization_token")
      },
      "goal_identity" => deep_copy(truth.dig("current_phase_route", "goal_identity")),
      "founder_reserved_profile" => deep_copy(truth.dig("current_phase_route", "founder_reserved_profile")),
      "acceptance_criteria" => ["exact bounded fixture passes"],
      "required_evidence" => ["fixture receipt"],
      "stop_conditions" => ["authority drift"],
      "forbidden_actions" => ["network"]
    }
    if File.exist?(contract_path)
      register_owned(contract_path)
      rewrite_owned(contract_path, YAML.dump(contract))
    else
      create_exclusive(contract_path, YAML.dump(contract))
    end
    contract_bytes = File.binread(contract_path)
    contract_sha = Digest::SHA256.hexdigest(contract_bytes)

    branch = "codex/test-current-authority-active"
    worktree = File.join(fixture["worktree_root"], "active")
    evidence = File.join(fixture["evidence_base"], "active-task")
    FileUtils.mkdir_p(evidence)
    authorization_id = Digest::SHA256.hexdigest("#{task_id}:fixture-authority")
    parent_commit = shell(repo, "git", "rev-parse", "HEAD").strip
    parent_tree = shell(repo, "git", "rev-parse", "HEAD^{tree}").strip
    authority_path = File.join(fixture["external"], "task-authority.yaml")
    authority = {
      "schema_version" => 1,
      "record_type" => "aios_phase_delegated_task_authority",
      "task_id" => task_id,
      "phase" => "P1",
      "route_id" => route_id,
      "status" => "ACTIVE",
      "authorization_id" => authorization_id,
      "task_contract_sha256" => contract_sha,
      "execution_nonce" => Digest::SHA256.hexdigest("#{task_id}:fixture-nonce"),
      "activation_parent" => { "commit" => parent_commit, "tree" => parent_tree },
      "branch" => branch,
      "worktree" => worktree,
      "evidence_root" => evidence,
      "budget" => budget,
      "roles" => roles,
      "allowlisted_paths" => allowlisted,
      "external_effects" => deep_copy(truth.fetch("current_phase_route").fetch("envelope").fetch("external_effects")),
      "founder_reserved_authorization" => deep_copy(contract.fetch("founder_reserved_authorization")),
      "goal_identity" => deep_copy(truth.dig("current_phase_route", "goal_identity")),
      "founder_reserved_profile" => deep_copy(truth.dig("current_phase_route", "founder_reserved_profile"))
    }
    create_exclusive(authority_path, YAML.dump(authority))
    authority_bytes = File.binread(authority_path)
    authority_sha = Digest::SHA256.hexdigest(authority_bytes)

    truth["goal"]["current_task_authority"] = task_id
    truth["project"]["phase_execution_status"] = "ACTIVE"
    truth["project"]["p1_execution_status"] = "ACTIVE"
    truth["current_phase_route"]["status"] = "ACTIVE"
    truth["current_phase_route"]["first_task"]["status"] = "ACTIVE"
    truth["current_phase_route"]["next_eligible_action"] = "CONTINUE_CURRENT_TASK"
    truth["active_work"] = {
      "current_task" => task_id,
      "current_task_status" => "ACTIVE",
      "current_task_contract" => {
        "path" => contract_relative,
        "sha256" => contract_sha,
        "byte_length" => contract_bytes.bytesize
      },
      "current_task_contract_sha256" => contract_sha,
      "current_execution_authorization" => authority_path,
      "current_execution_authorization_sha256" => authority_sha,
      "authority_record" => {
        "path" => authority_path,
        "sha256" => authority_sha,
        "byte_length" => authority_bytes.bytesize
      },
      "execution_nonce" => Digest::SHA256.hexdigest("#{task_id}:fixture-nonce"),
      "execution_nonce_status" => "ACTIVE",
      "authorization_id" => authorization_id,
      "activation_parent_commit" => parent_commit,
      "activation_parent_tree" => parent_tree,
      "task_resource_state" => "ACTIVE",
      "task_branch" => branch,
      "task_worktree" => worktree,
      "execution_evidence_root" => evidence,
      "allowlisted_paths" => allowlisted,
      "budget" => budget,
      "roles" => roles,
      "external_effects" => deep_copy(truth.fetch("current_phase_route").fetch("envelope").fetch("external_effects")),
      "offsite_target" => nil,
      "founder_reserved_authorization" => truth.dig("current_phase_route", "decision_packet", "path"),
      "founder_reserved_authorization_sha256" => truth.dig("current_phase_route", "decision_packet", "sha256"),
      "founder_decision_required" => false,
      "escalation_reason" => nil,
      "user_action_required" => "NONE",
      "next_eligible_action" => "CONTINUE_CURRENT_TASK"
    }
    dump_owned_yaml(truth_path, truth)
    commit(repo, "test: activate generic phase-local task")
    shell(repo, "git", "worktree", "add", "--quiet", "-b", branch, worktree, "HEAD")

    fixture.merge(
      "task_id" => task_id,
      "contract_path" => contract_path,
      "contract_bytes" => contract_bytes,
      "authority_path" => authority_path,
      "authority_bytes" => authority_bytes,
      "task_worktree" => worktree,
      "task_branch" => branch
    )
  end

  def bind_authority_to_truth(fixture, truth, authority)
    dump_owned_yaml(fixture["authority_path"], authority)
    bytes = File.binread(fixture["authority_path"])
    sha = Digest::SHA256.hexdigest(bytes)
    truth["active_work"]["current_execution_authorization_sha256"] = sha
    truth["active_work"]["authority_record"] = {
      "path" => fixture["authority_path"],
      "sha256" => sha,
      "byte_length" => bytes.bytesize
    }
  end

  def bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    dump_owned_yaml(fixture["contract_path"], contract)
    bytes = File.binread(fixture["contract_path"])
    sha = Digest::SHA256.hexdigest(bytes)
    truth["active_work"]["current_task_contract"] = {
      "path" => truth.dig("current_phase_route", "first_task", "contract_path"),
      "sha256" => sha,
      "byte_length" => bytes.bytesize
    }
    truth["active_work"]["current_task_contract_sha256"] = sha
    authority["task_contract_sha256"] = sha
    bind_authority_to_truth(fixture, truth, authority)
  end

  def commit_truth(fixture, truth, message)
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(fixture["repo"], message)
  end

  def expect_dual_nonpass(fixture, label, pattern)
    expect_nonpass(fixture["repo"], "#{label} main", pattern)
    expect_safety_nonpass(fixture["repo"], fixture["truth_path"], "#{label} safety", pattern)
  end

  def active_tests(fixture)
    repo = fixture["repo"]
    expect_pass(repo, "mapping-only roles active Task")
    expect_safety_pass(repo, fixture["truth_path"], "mapping-only roles active Task safety")

    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    original_owner = contract.fetch("roles").fetch("owner")
    contract["roles"]["owner"] = "Fixture Contract Drift"
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: drift Contract role mapping")
    expect_dual_nonpass(fixture, "Contract role mismatch", /contract roles mismatch/)
    truth = yaml(fixture["truth_path"])
    contract = yaml(fixture["contract_path"])
    authority = yaml(fixture["authority_path"])
    contract["roles"]["owner"] = original_owner
    bind_contract_and_authority_to_truth(fixture, truth, contract, authority)
    commit_truth(fixture, truth, "test: restore Contract role mapping")
    expect_pass(repo, "Contract role mapping restored")
    expect_safety_pass(repo, fixture["truth_path"], "Contract role mapping safety restored")

    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    original_owner = authority.fetch("roles").fetch("owner")
    authority["roles"]["owner"] = "Fixture Authority Drift"
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: drift Authority role mapping")
    expect_dual_nonpass(fixture, "Authority role mismatch", /authority record roles mismatch/)
    truth = yaml(fixture["truth_path"])
    authority = yaml(fixture["authority_path"])
    authority["roles"]["owner"] = original_owner
    bind_authority_to_truth(fixture, truth, authority)
    commit_truth(fixture, truth, "test: restore Authority role mapping")
    expect_pass(repo, "Authority role mapping restored")
    expect_safety_pass(repo, fixture["truth_path"], "Authority role mapping safety restored")

    truth = yaml(fixture["truth_path"])
    original_owner = truth.dig("active_work", "roles", "owner")
    truth["active_work"]["roles"]["owner"] = "Fixture Truth Drift"
    commit_truth(fixture, truth, "test: drift Truth role mapping")
    expect_dual_nonpass(fixture, "Truth role mismatch", /contract roles mismatch/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["roles"]["owner"] = original_owner
    commit_truth(fixture, truth, "test: restore Truth role mapping")
    expect_pass(repo, "Truth role mapping restored")
    expect_safety_pass(repo, fixture["truth_path"], "Truth role mapping safety restored")

    original = tamper_owned_byte(fixture["authority_path"])
    expect_nonpass(repo, "authority record byte tamper", /authority record SHA-256 mismatch/)
    restore_owned_byte(fixture["authority_path"], original)

    original = tamper_owned_byte(fixture["contract_path"])
    shell(repo, "git", "add", fixture["contract_path"])
    shell(repo, "git", "commit", "-m", "test: tamper owned contract bytes")
    expect_nonpass(repo, "Task Contract byte tamper", /active Task contract SHA-256 mismatch/)
    restore_owned_byte(fixture["contract_path"], original)
    commit(repo, "test: restore owned contract bytes")

    truth = yaml(fixture["truth_path"])
    original_network = truth["active_work"]["external_effects"]["network"]
    truth["active_work"]["external_effects"]["network"] = !original_network
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: set unauthorized external effect")
    expect_dual_nonpass(fixture, "unauthorized network-effect drift",
                        /exact authorized external-effect map/)
    truth["active_work"]["external_effects"]["network"] = original_network
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: restore external effects")

    truth = yaml(fixture["truth_path"])
    original_hours = truth["active_work"]["budget"]["engineering_hours"]
    truth["active_work"]["budget"]["engineering_hours"] = original_hours + 1
    commit_truth(fixture, truth, "test: drift active Task budget")
    expect_dual_nonpass(fixture, "active budget mismatch", /contract budget engineering_hours mismatch/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["budget"]["engineering_hours"] = original_hours
    commit_truth(fixture, truth, "test: restore active Task budget")

    truth = yaml(fixture["truth_path"])
    original_repairs = truth["current_phase_route"]["envelope"]["max_same_task_repairs"]
    truth["current_phase_route"]["envelope"]["max_same_task_repairs"] = original_repairs + 1
    commit_truth(fixture, truth, "test: expand repair allowance")
    expect_dual_nonpass(fixture, "repair allowance mismatch", /max_same_task_repairs does not match/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["envelope"]["max_same_task_repairs"] = original_repairs
    commit_truth(fixture, truth, "test: restore repair allowance")

    truth = yaml(fixture["truth_path"])
    truth["active_work"]["allowlisted_paths"] << "README.md"
    commit_truth(fixture, truth, "test: grant path outside reviewed Contract")
    expect_dual_nonpass(fixture, "allowlisted path mismatch", /outside the reviewed Contract maximum scope/)
    truth = yaml(fixture["truth_path"])
    truth["active_work"]["allowlisted_paths"].delete("README.md")
    commit_truth(fixture, truth, "test: restore allowlisted paths")

    truth = yaml(fixture["truth_path"])
    truth["phase_boundary"]["allowed_capabilities"] << "AGENT_SHELL"
    commit_truth(fixture, truth, "test: admit deferred capability")
    expect_pass(repo, "authority core does not duplicate deferred-capability policy")
    expect_safety_nonpass(repo, fixture["truth_path"], "safety rejects deferred capability",
                          /P1 admits a deferred capability/)
    truth = yaml(fixture["truth_path"])
    truth["phase_boundary"]["allowed_capabilities"].delete("AGENT_SHELL")
    commit_truth(fixture, truth, "test: restore deferred capability boundary")
    expect_pass(repo, "deferred capability boundary restored")
    expect_safety_pass(repo, fixture["truth_path"], "deferred capability safety restored")

    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["additional_write_roots"] << "outside-p1-owned-root"
    commit_truth(fixture, truth, "test: add route write root outside P1 boundary")
    expect_pass(repo, "authority core leaves P1 write-root policy to safety")
    expect_safety_nonpass(repo, fixture["truth_path"], "safety rejects out-of-bound write root",
                          /route write root is outside the P1 boundary/)
    truth = yaml(fixture["truth_path"])
    truth["current_phase_route"]["additional_write_roots"].delete("outside-p1-owned-root")
    commit_truth(fixture, truth, "test: restore route write roots")
    expect_pass(repo, "route write roots restored")
    expect_safety_pass(repo, fixture["truth_path"], "route write-root safety restored")

    truth = yaml(fixture["truth_path"])
    truth["task_history"]["fixture_reuse"] = { "task_id" => fixture["task_id"], "status" => "HISTORICAL" }
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: inject historical Task id collision")
    expect_nonpass(repo, "historical Task id reuse", /reuses historical|reuses a historical/)
    truth["task_history"].delete("fixture_reuse")
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: remove historical Task id collision")

    extra = File.join(fixture["worktree_root"], "extra")
    shell(repo, "git", "worktree", "add", "--quiet", "-b", "codex/test-current-authority-extra", extra, "HEAD")
    expect_nonpass(repo, "undeclared extra worktree", /Git worktree set does not equal/)
    shell(repo, "git", "worktree", "remove", extra)
    shell(repo, "git", "branch", "-d", "codex/test-current-authority-extra")
    expect_pass(repo, "active Task after owned extra worktree cleanup")

    shell(repo, "git", "worktree", "remove", fixture["task_worktree"])
    shell(repo, "git", "branch", "-d", fixture["task_branch"])
    truth = yaml(fixture["truth_path"])
    truth["goal"]["current_task_authority"] = "NONE"
    truth["project"]["phase_execution_status"] = "ACTIVE"
    truth["project"]["p1_execution_status"] = "ACTIVE"
    truth["current_phase_route"]["status"] = "ACTIVE"
    truth["current_phase_route"]["first_task"]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
    truth["current_phase_route"]["next_eligible_action"] = "MASTER_SELECT_NEXT_PHASE_LOCAL_TASK"
    truth["current_phase_route"].delete("active_task")
    truth["task_history"]["fixture_completed_first_task"] = {
      "task_id" => fixture["task_id"],
      "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
    }
    truth["active_work"] = ready_active_work
    truth["active_work"]["task_resource_state"] = "NONE_PHASE_ACTIVE"
    truth["active_work"]["next_eligible_action"] = "MASTER_SELECT_NEXT_PHASE_LOCAL_TASK"
    dump_owned_yaml(fixture["truth_path"], truth)
    commit(repo, "test: enter between-Task active Phase idle")
    expect_pass(repo, "between-Task active Phase with Task NONE")
  end

  def run
    sandbox = Dir.mktmpdir("sourcelens-current-authority-")
    sandbox_identity = nil
    begin
      sandbox_stat = File.lstat(sandbox)
      assert(sandbox_stat.directory? && !sandbox_stat.symlink?, "temporary root is not an owned directory")
      sandbox_identity = [sandbox_stat.dev, sandbox_stat.ino]
      fixture = prepare_fixture(sandbox)
      ready_tests(fixture)
      fixture = activate_fixture(fixture)
      active_tests(fixture)
    ensure
      if sandbox_identity
        current = File.lstat(sandbox)
        assert(current.directory? && !current.symlink? && [current.dev, current.ino] == sandbox_identity,
               "temporary root identity changed before cleanup")
        FileUtils.remove_entry_secure(sandbox)
      end
    end
    puts "CURRENT_TASK_AUTHORITY_TESTS: PASS assertions=#{@passes}"
  end
end

begin
  CurrentTaskAuthorityTest.new.run
  exit 0
rescue TestFailure => e
  warn "CURRENT_TASK_AUTHORITY_TESTS: NON_PASS #{e.message}"
  exit 1
rescue StandardError => e
  warn "CURRENT_TASK_AUTHORITY_TESTS: NON_PASS unexpected #{e.class}: #{e.message}"
  warn e.backtrace.first(5).join("\n")
  exit 1
end

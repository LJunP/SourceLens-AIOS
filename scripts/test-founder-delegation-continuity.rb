#!/usr/bin/env ruby
# frozen_string_literal: true

require "fileutils"
require "digest"
require "json"
require "open3"
require "tmpdir"
require "yaml"

require_relative "validate-founder-delegation-continuity"

ROOT = File.expand_path("..", __dir__)
TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
VALIDATOR = File.join(ROOT, "scripts/validate-founder-delegation-continuity.rb")
TERMINATION_DECISION_FIXTURE_ENV = "SOURCE_LENS_TERMINATION_DECISION_FIXTURE"
TERMINATION_HUMAN_FIXTURE_ENV = "SOURCE_LENS_TERMINATION_HUMAN_FIXTURE"

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def fixture_validator_source(durable_evidence_root: nil)
  source = File.binread(VALIDATOR)
  physical_root_check = [
    "  def validate_goal_termination_physical_root!(root)",
    "    expected = Pathname.new(GOAL_TERMINATION_CANONICAL_REPOSITORY).realpath",
    "    actual = Pathname.new(root).realpath",
    "    assert(actual == expected,"
  ].join("\n")
  fixture_physical_root_check = [
    "  def validate_goal_termination_physical_root!(root)",
    "    expected = [",
    "      Pathname.new(GOAL_TERMINATION_CANONICAL_REPOSITORY).realpath,",
    "      Pathname.new(#{File.realpath(ROOT).dump}).realpath",
    "    ]",
    "    actual = Pathname.new(root).realpath",
    "    assert(expected.include?(actual),"
  ].join("\n")
  raise "fixture validator physical-root check is not unique" unless
    source.split(physical_root_check, -1).length == 2
  source = source.sub(physical_root_check, fixture_physical_root_check)

  return source if durable_evidence_root.nil?

  original_root = FounderDelegationContinuity::GOAL_TERMINATION_DURABLE_EVIDENCE_ROOT.dump
  fixture_root = durable_evidence_root.dump
  raise "fixture validator durable-root anchor is not unique" unless
    source.split(original_root, -1).length == 2
  source.sub(original_root, fixture_root)
end

def run_fixture(root, name, truth)
  path = File.join(root, "#{name}.yaml")
  validator_path = File.join(root, "#{name}-validator.rb")
  File.binwrite(path, YAML.dump(truth))
  File.binwrite(validator_path, fixture_validator_source)
  Open3.capture3("ruby", validator_path, "--fixture", path, chdir: ROOT)
end

def run_fixture_with_durable_evidence_root(root, name, truth, durable_evidence_root)
  path = File.join(root, "#{name}.yaml")
  validator_path = File.join(root, "#{name}-validator.rb")
  File.binwrite(path, YAML.dump(truth))

  File.binwrite(
    validator_path,
    fixture_validator_source(durable_evidence_root: durable_evidence_root)
  )
  Open3.capture3("ruby", validator_path, "--fixture", path, chdir: ROOT)
end

def identity_for(path)
  bytes = File.binread(path)
  {
    "path" => File.realpath(path),
    "byte_length" => bytes.bytesize,
    "sha256" => Digest::SHA256.hexdigest(bytes)
  }
end

def write_json_identity(root, name, value)
  path = File.join(root, name)
  File.binwrite(path, JSON.generate(value))
  identity_for(path)
end

def write_compact_json_identity(root, name, value)
  path = File.join(root, name)
  File.binwrite(path, JSON.generate(value) + "\n")
  identity_for(path)
end

def recursively_sorted_json(value)
  sorted = lambda do |item|
    case item
    when Hash
      item.keys.sort.to_h { |key| [key, sorted.call(item[key])] }
    when Array
      item.map { |child| sorted.call(child) }
    else
      item
    end
  end
  JSON.generate(sorted.call(value))
end

def write_canonical_json_identity(root, name, value)
  path = File.join(root, name)
  File.binwrite(path, recursively_sorted_json(value) + "\n")
  identity_for(path)
end

def rehash_knowledge_event!(event)
  event["event_sha256"] = Digest::SHA256.hexdigest(
    recursively_sorted_json(event.reject { |key, _value| key == "event_sha256" })
  )
end

def rehash_knowledge_chain!(events, start_index = 0)
  (start_index...events.length).each do |index|
    events[index]["previous_event_sha256"] = index.zero? ? nil : events[index - 1]["event_sha256"]
    rehash_knowledge_event!(events[index])
  end
end

def git_fixture!(root, *arguments)
  stdout, stderr, status = Open3.capture3("git", *arguments, chdir: root)
  raise "fixture Git command failed: git #{arguments.join(' ')}\n#{stdout}#{stderr}" unless
    status.success?
  stdout.strip
end

def write_bytes_identity(root, name, bytes)
  path = File.join(root, name)
  File.binwrite(path, bytes)
  identity_for(path)
end

def synchronously_rebind_terminal_inventory(fixtures, receipt, fixture_prefix)
  evidence = receipt.fetch("evidence_bindings")
  full_inventory = JSON.parse(File.binread(
    evidence.fetch("formal_dev_repeat_003_full_file_inventory").fetch("path")
  ))
  yield full_inventory
  inventory_identity = write_json_identity(
    fixtures, "#{fixture_prefix}-inventory.json", full_inventory
  )

  run_receipt = JSON.parse(File.binread(
    evidence.fetch("formal_dev_repeat_003_terminal_receipt").fetch("path")
  ))
  run_root = run_receipt.fetch("run_root")
  run_root["path"] = full_inventory.fetch("run_root")
  run_inventory = run_root.fetch("full_file_inventory")
  run_inventory["path"] = inventory_identity["path"]
  run_inventory["byte_length"] = inventory_identity["byte_length"]
  run_inventory["sha256"] = inventory_identity["sha256"]
  %w[
    file_count directory_count symlink_count aggregate_regular_file_bytes
    file_projection_sha256 directory_projection_sha256
  ].each { |key| run_inventory[key] = full_inventory.fetch(key) }
  run_identity = write_json_identity(
    fixtures, "#{fixture_prefix}-run-receipt.json", run_receipt
  )

  quality = JSON.parse(File.binread(
    evidence.fetch("formal_dev_repeat_003_terminal_quality_non_pass").fetch("path")
  ))
  quality.fetch("run003")["run_root"] = full_inventory.fetch("run_root")
  quality_identity = write_json_identity(
    fixtures, "#{fixture_prefix}-quality-receipt.json", quality
  )

  review = JSON.parse(File.binread(
    evidence.fetch("independent_terminal_task_review").fetch("path")
  ))
  review_run = review.fetch("exact_run003_bindings")
  review_run["run_root"] = full_inventory.fetch("run_root")
  review_inventory = review_run.fetch("full_file_inventory")
  review_inventory["path"] = inventory_identity["path"]
  review_inventory["byte_length"] = inventory_identity["byte_length"]
  review_inventory["sha256"] = inventory_identity["sha256"]
  %w[
    file_count directory_count symlink_count aggregate_regular_file_bytes
    file_projection_sha256 directory_projection_sha256
  ].each { |key| review_inventory[key] = full_inventory.fetch(key) }
  review_run_receipt = review_run.fetch("run_terminal_receipt")
  review_run_receipt["path"] = run_identity["path"]
  review_run_receipt["byte_length"] = run_identity["byte_length"]
  review_run_receipt["sha256"] = run_identity["sha256"]
  review_quality = review.fetch("authority_bindings").fetch(
    "run003_terminal_quality_receipt"
  )
  review_quality["path"] = quality_identity["path"]
  review_quality["byte_length"] = quality_identity["byte_length"]
  review_quality["sha256"] = quality_identity["sha256"]
  review_identity = write_json_identity(
    fixtures, "#{fixture_prefix}-independent-review.json", review
  )

  evidence["formal_dev_repeat_003_full_file_inventory"] = inventory_identity
  evidence["formal_dev_repeat_003_terminal_receipt"] = run_identity
  evidence["formal_dev_repeat_003_terminal_quality_non_pass"] = quality_identity
  evidence["independent_terminal_task_review"] = review_identity
  receipt.fetch("independent_terminal_review")["identity"] = deep_copy(review_identity)
  receipt
end

def bind_strategic_decision(truth, identity)
  truth.fetch("founder_escalation_control").fetch("resolution")["structured_decision"] =
    deep_copy(identity)
  truth.fetch("current_phase_route")["founder_decision"] = deep_copy(identity)
  truth.fetch("active_work")["founder_reserved_authorization"] = identity.fetch("path")
  truth.fetch("active_work")["founder_reserved_authorization_sha256"] = identity.fetch("sha256")
end

def bind_goal_termination_decision(truth, decision_identity, human_identity)
  truth.fetch("goal")["termination_decision"] = deep_copy(decision_identity)
  truth.fetch("current_phase_route")["founder_decision"] = deep_copy(decision_identity)
  resolution = truth.fetch("founder_escalation_control").fetch("resolution")
  resolution["structured_decision"] = deep_copy(decision_identity)
  resolution["human_record"] = deep_copy(human_identity)
  active = truth.fetch("active_work")
  active["founder_reserved_authorization"] = decision_identity.fetch("path")
  active["founder_reserved_authorization_sha256"] = decision_identity.fetch("sha256")
  active["founder_termination_decision"] = deep_copy(decision_identity)
end

def termination_source_path(declared_path, environment_key)
  return declared_path if declared_path.is_a?(String) && File.file?(declared_path)

  replacement = ENV[environment_key]
  raise "#{environment_key} must name the frozen termination Evidence for pre-install tests" unless
    replacement.is_a?(String) && File.file?(replacement)
  replacement
end

def materialize_goal_termination_evidence!(truth, fixtures)
  return nil unless truth.dig("current_phase_route", "schema_version") ==
                    FounderDelegationContinuity::GOAL_TERMINATION_ROUTE_SCHEMA

  declared_decision = truth.dig("current_phase_route", "founder_decision", "path")
  declared_human = truth.dig(
    "founder_escalation_control", "resolution", "human_record", "path"
  )
  if File.file?(declared_decision.to_s) && File.file?(declared_human.to_s)
    return JSON.parse(File.binread(declared_decision))
  end
  decision_source = termination_source_path(
    declared_decision, TERMINATION_DECISION_FIXTURE_ENV
  )
  human_source = termination_source_path(declared_human, TERMINATION_HUMAN_FIXTURE_ENV)
  decision_path = File.join(fixtures, File.basename(declared_decision))
  human_path = File.join(fixtures, File.basename(declared_human))
  File.binwrite(decision_path, File.binread(decision_source))
  File.binwrite(human_path, File.binread(human_source))
  decision_identity = identity_for(decision_path)
  human_identity = identity_for(human_path)
  bind_goal_termination_decision(truth, decision_identity, human_identity)
  JSON.parse(File.binread(decision_path))
end

def expect_pass(root, name, truth, expected)
  stdout, stderr, status = run_fixture(root, name, truth)
  raise "#{name} unexpectedly failed\n#{stdout}#{stderr}" unless status.success?
  raise "#{name} disposition drift\n#{stdout}" unless stdout.include?("disposition=#{expected}")
end

def expect_non_pass(root, name, truth, expected_fragment)
  stdout, stderr, status = run_fixture(root, name, truth)
  raise "#{name} unexpectedly passed\n#{stdout}#{stderr}" if status.success?
  combined = stdout + stderr
  raise "#{name} failed for the wrong reason\n#{combined}" unless combined.include?(expected_fragment)
end

def expect_non_pass_with_durable_evidence_root(root, name, truth, durable_evidence_root,
                                               expected_fragment)
  stdout, stderr, status = run_fixture_with_durable_evidence_root(
    root, name, truth, durable_evidence_root
  )
  raise "#{name} unexpectedly passed\n#{stdout}#{stderr}" if status.success?
  combined = stdout + stderr
  raise "#{name} failed for the wrong reason\n#{combined}" unless combined.include?(expected_fragment)
end

def expect_method_non_pass(name, expected_fragment)
  yield
  raise "#{name} unexpectedly passed"
rescue FounderDelegationContinuityError => e
  raise "#{name} failed for the wrong reason\n#{e.message}" unless e.message.include?(expected_fragment)
end

def expect_method_pass(name)
  yield
rescue StandardError => e
  raise "#{name} unexpectedly failed\n#{e.class}: #{e.message}"
end

current_truth = YAML.safe_load(
  File.binread(TRUTH),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

route_literal = "AIOS-P2-058_DEV_FIRST_GRAPH_CONTEXT_VALUE_BENCHMARK_PHASE_DELEGATED_ROUTE"
commits, stderr, status = Open3.capture3(
  "git", "log", "--reverse", "--format=%H", "--",
  "docs/aios/truth/project_state.yaml", chdir: ROOT
)
raise "cannot resolve delegated active Truth history: #{stderr}" unless status.success?
historical_truths = []
active_truths = commits.lines.map(&:strip).reject(&:empty?).each_with_object([]) do |commit, values|
  bytes, _show_stderr, show_status = Open3.capture3(
    "git", "show", "#{commit}:docs/aios/truth/project_state.yaml", chdir: ROOT
  )
  next unless show_status.success?
  begin
    candidate = YAML.safe_load(bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
  rescue Psych::BadAlias, Psych::SyntaxError
    next
  end
  historical_truths << candidate
  route = candidate["current_phase_route"]
  values << candidate if route.is_a?(Hash) && route["route_id"] == route_literal && route["status"] == "ACTIVE"
end
base = active_truths.last
raise "delegated active Truth anchor is missing" unless base
base.fetch("phase_execution_envelope").fetch("task_ledger").each do |entry|
  entry.delete("capacity_source_task_id")
end
base["phase_boundary"] = deep_copy(current_truth.fetch("phase_boundary"))
reserved_base = historical_truths.reverse.find do |candidate|
  candidate.dig("founder_escalation_control", "schema_version") == "founder-escalation-control/v1" &&
    candidate.dig("founder_escalation_control", "reserved_trigger", "evidence", "path").is_a?(String) &&
    candidate.dig("phase_execution_envelope", "status") == "EXHAUSTED"
end
raise "Founder reserved Truth anchor is missing" unless reserved_base

terminal_schema = FounderDelegationContinuity::PRE_CANDIDATE_TERMINAL_RECEIPT_ADAPTERS.keys.fetch(0)
terminal_contract_path = File.join(
  ROOT, "docs/aios/tasks/P2-064_SOURCE_LOCAL_IMPORT_CONTEXT_PRODUCT_EXPERIMENT.yaml"
)
terminal_contract_identity = identity_for(terminal_contract_path)
terminal_fixture_truth = ([current_truth] + historical_truths.reverse).find do |candidate|
  next false if candidate.dig("current_phase_route", "schema_version") ==
                FounderDelegationContinuity::GOAL_TERMINATION_ROUTE_SCHEMA
  Array(candidate.dig("phase_execution_envelope", "task_ledger")).any? do |entry|
    next false unless entry.is_a?(Hash) &&
                      entry.dig("contract", "sha256") == terminal_contract_identity["sha256"] &&
                      entry.dig("contract", "byte_length") == terminal_contract_identity["byte_length"]
    receipt_path = entry.dig("outcome_receipt", "path")
    next false unless receipt_path.is_a?(String) && File.file?(receipt_path)

    JSON.parse(File.binread(receipt_path))["schema_version"] == terminal_schema
  rescue JSON::ParserError
    false
  end
end
raise "durable pre-candidate terminal fixture is missing" unless terminal_fixture_truth
terminal_entry = terminal_fixture_truth.fetch("phase_execution_envelope").fetch("task_ledger").find do |entry|
  entry.is_a?(Hash) && entry.dig("contract", "sha256") == terminal_contract_identity["sha256"] &&
    File.file?(entry.dig("outcome_receipt", "path").to_s) &&
    JSON.parse(File.binread(entry.dig("outcome_receipt", "path")))["schema_version"] == terminal_schema
end
raise "durable pre-candidate terminal ledger entry is missing" unless terminal_entry
terminal_receipt = JSON.parse(File.binread(terminal_entry.dig("outcome_receipt", "path")))
terminal_contract = YAML.safe_load(
  File.binread(terminal_contract_path),
  permitted_classes: [], permitted_symbols: [], aliases: false
)
terminal_source_route_ref = terminal_fixture_truth.dig(
  "phase_execution_envelope", "authority_basis", "source_route_ref"
)
terminal_source_route = terminal_fixture_truth.fetch(terminal_source_route_ref)
terminal_source_decision = JSON.parse(File.binread(terminal_source_route.dig("decision_packet", "path")))
terminal_anchor_commit, = FounderDelegationContinuity.first_task_ledger_anchor!(
  ROOT,
  terminal_entry,
  terminal_entry.dig("outcome_receipt", "sha256"),
  "durable pre-candidate terminal fixture"
)
active_fixture_truth = FounderDelegationContinuity.truth_at_commit(
  ROOT,
  terminal_receipt.dig("canonical_before_terminal_sync", "commit"),
  "durable single-Task ACTIVE fixture"
)
active_source_route_ref = active_fixture_truth.dig(
  "phase_execution_envelope", "authority_basis", "source_route_ref"
)
active_source_route = active_fixture_truth.fetch(active_source_route_ref)

Dir.mktmpdir("founder-delegation-continuity-") do |fixtures|
  assertions = 0

  termination_decision = materialize_goal_termination_evidence!(current_truth, fixtures)
  termination_final =
    current_truth.dig("current_phase_route", "schema_version") ==
      FounderDelegationContinuity::GOAL_TERMINATION_ROUTE_SCHEMA &&
    current_truth.dig("termination_schema_amendment", "status") == "FOUNDER_AUTHORIZED_FINAL"

  current_disposition = current_truth.fetch("founder_escalation_control").fetch("disposition")
  if termination_decision && !termination_final
    expect_non_pass(
      fixtures, "current-termination-candidate-remains-fail-closed-before-additive-authorization",
      current_truth, "terminal-schema amendment is not Founder-authorized final"
    )
  else
    expect_pass(fixtures, "current-canonical-delegation-disposition", current_truth,
                current_disposition)
  end
  assertions += 1

  expect_method_pass("goal-termination-exact-canonical-physical-root-pass") do
    FounderDelegationContinuity.validate_goal_termination_physical_root!(
      FounderDelegationContinuity::GOAL_TERMINATION_CANONICAL_REPOSITORY
    )
  end
  assertions += 1

  expect_method_non_pass("goal-termination-secondary-physical-root-rejected",
                         "exact canonical physical repository root") do
    FounderDelegationContinuity.validate_goal_termination_physical_root!(fixtures)
  end
  assertions += 1

  if termination_decision
    termination_resolution = current_truth.dig("founder_escalation_control", "resolution")
    termination_decision_identity = termination_resolution.fetch("structured_decision")
    termination_amendment_binding = current_truth.fetch("termination_schema_amendment")
    whole_truth_delta = lambda do |candidate_truth|
      FounderDelegationContinuity.validate_goal_termination_whole_truth_delta!(
        ROOT, candidate_truth, termination_decision, termination_decision_identity,
        termination_resolution, candidate_truth.fetch("termination_schema_amendment")
      )
    end
    expect_method_pass("goal-termination-whole-truth-exact-parent-delta-pass") do
      whole_truth_delta.call(current_truth)
    end
    assertions += 1

    whole_truth_mutations = {
      "authority-founder" => lambda { |truth| truth.fetch("authority")["founder"] = "Agent" },
      "authority-rule" => lambda { |truth| truth.fetch("authority")["rule"] = "drift" },
      "authority-status" => lambda do |truth|
        truth.dig("authority", "strategy")["status"] = "ACTIVE"
      end,
      "unused-history-root" => lambda do |truth|
        truth.fetch("historical_p2_064_phase_route")["unexpected_terminal_claim"] = true
      end,
      "goal-note" => lambda { |truth| truth.fetch("goal")["note"] += " DRIFT" },
      "phase-claim-text" => lambda do |truth|
        truth.fetch("phase_delegation")["claim_boundary"] = "DRIFT"
      end,
      "verification-timestamp" => lambda do |truth|
        truth["last_verified_at"] = "2026-08-10T02:00:00Z"
      end,
      "verification-scope" => lambda { |truth| truth["verification_scope"] = "DRIFT" },
      "phase-execution-claim" => lambda do |truth|
        truth.fetch("phase_execution_claim")["current_route_claim"] = "DRIFT"
      end,
      "extra-authority" => lambda do |truth|
        truth.fetch("authority")["terminal_override"] = true
      end,
      "extra-production-claim" => lambda { |truth| truth["production_ready"] = true }
    }
    whole_truth_mutations.each do |name, mutate|
      truth = deep_copy(current_truth)
      mutate.call(truth)
      expect_method_non_pass("goal-termination-whole-truth-#{name}",
                             "whole-Truth terminal delta drifts") do
        whole_truth_delta.call(truth)
      end
      assertions += 1
    end

    knowledge_append = lambda do |candidate_truth|
      FounderDelegationContinuity.validate_goal_termination_knowledge_append!(
        ROOT, candidate_truth, termination_decision
      )
    end
    expect_method_pass("goal-termination-knowledge-exact-parent-prefix-pass") do
      knowledge_append.call(current_truth)
    end
    assertions += 1

    truth = deep_copy(current_truth)
    events = truth.dig("founder_knowledge_sync", "events")
    events.delete_at(events.length - 2)
    rehash_knowledge_chain!(events, events.length - 1)
    expect_method_non_pass("goal-termination-knowledge-parent-event-delete",
                           "exactly one Knowledge event suffix") do
      knowledge_append.call(truth)
    end
    assertions += 1

    truth = deep_copy(current_truth)
    events = truth.dig("founder_knowledge_sync", "events")
    events[-3], events[-2] = events[-2], events[-3]
    rehash_knowledge_chain!(events, events.length - 3)
    expect_method_non_pass("goal-termination-knowledge-parent-event-reorder",
                           "event prefix drifts") do
      knowledge_append.call(truth)
    end
    assertions += 1

    truth = deep_copy(current_truth)
    events = truth.dig("founder_knowledge_sync", "events")
    events[-2]["rationale"] += " coherent rehash drift"
    rehash_knowledge_chain!(events, events.length - 2)
    expect_method_non_pass("goal-termination-knowledge-parent-event-coherent-rehash",
                           "event prefix drifts") do
      knowledge_append.call(truth)
    end
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("founder_knowledge_sync", "inherited_knowledge_compatibility")["status"] =
      "DRIFT"
    expect_method_non_pass("goal-termination-knowledge-compatibility-metadata-drift",
                           "Knowledge static metadata drift") do
      knowledge_append.call(truth)
    end
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("founder_knowledge_sync")["vault_path"] = "/private/tmp/drift-vault"
    expect_method_non_pass("goal-termination-knowledge-vault-metadata-drift",
                           "Knowledge static metadata drift") do
      knowledge_append.call(truth)
    end
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("founder_knowledge_sync", "events") <<
      deep_copy(truth.dig("founder_knowledge_sync", "events").last)
    expect_method_non_pass("goal-termination-knowledge-second-suffix-rejected",
                           "exactly one Knowledge event suffix") do
      knowledge_append.call(truth)
    end
    assertions += 1

    parent_truth = FounderDelegationContinuity.truth_at_commit(
      ROOT, termination_decision.dig("binding", "canonical_repository", "commit"),
      "Goal termination Knowledge freshness fixture parent"
    )
    vault_root = current_truth.dig("founder_knowledge_sync", "vault_path")
    fresh_identity = lambda do |path, byte_length, digest_character|
      {"path" => path, "byte_length" => byte_length, "sha256" => digest_character * 64}
    end
    fresh_event = {
      "artifact" => fresh_identity.call(
        File.join(
          FounderDelegationContinuity::GOAL_TERMINATION_KNOWLEDGE_EVIDENCE_ROOT,
          "SOURCE_LENS_GOAL_TERMINATION_AFTER_P2_RESEARCH_NON_PASS_LEARNING_ARTIFACT.md"
        ), 101, "1"
      ),
      "review" => fresh_identity.call(
        File.join(
          FounderDelegationContinuity::GOAL_TERMINATION_KNOWLEDGE_EVIDENCE_ROOT,
          "SOURCE_LENS_GOAL_TERMINATION_AFTER_P2_RESEARCH_NON_PASS_KNOWLEDGE_REVIEW.json"
        ), 102, "2"
      ),
      "receipt" => fresh_identity.call(
        File.join(
          FounderDelegationContinuity::GOAL_TERMINATION_KNOWLEDGE_EVIDENCE_ROOT,
          "SOURCE_LENS_GOAL_TERMINATION_AFTER_P2_RESEARCH_NON_PASS_IMPORT_RECEIPT.json"
        ), 103, "3"
      ),
      "vault_import" => fresh_identity.call(
        FounderDelegationContinuity::GOAL_TERMINATION_KNOWLEDGE_VAULT_IMPORT_PATH,
        101, "1"
      )
    }
    fresh_receipt = {
      "truth_snapshot" => fresh_identity.call(
        FounderDelegationContinuity::GOAL_TERMINATION_KNOWLEDGE_TRUTH_SNAPSHOT_PATH,
        104, "4"
      )
    }
    fresh_receipt.fetch("truth_snapshot")["sha256"] =
      FounderDelegationContinuity::GOAL_TERMINATION_PARENT_TRUTH_SHA256
    freshness = lambda do |event, receipt|
      FounderDelegationContinuity.validate_goal_termination_knowledge_freshness!(
        parent_truth, current_truth.fetch("founder_knowledge_sync"), event, receipt
      )
    end
    expect_method_pass("goal-termination-knowledge-fresh-root-separation-pass") do
      freshness.call(fresh_event, fresh_receipt)
    end
    assertions += 1

    historical_artifact = parent_truth.dig("founder_knowledge_sync", "events").reverse
                                      .map { |event| event["artifact"] }
                                      .find { |identity| identity.is_a?(Hash) && identity["path"] }
    event = deep_copy(fresh_event)
    event["artifact"]["byte_length"] = historical_artifact["byte_length"]
    event["artifact"]["sha256"] = historical_artifact["sha256"]
    expect_method_non_pass("goal-termination-knowledge-historical-identity-reuse",
                           "reuses a parent identity or path") do
      freshness.call(event, fresh_receipt)
    end
    assertions += 1

    event = deep_copy(fresh_event)
    event["artifact"] = deep_copy(event["vault_import"])
    expect_method_non_pass("goal-termination-knowledge-artifact-equals-vault-path",
                           "paths are not distinct") do
      freshness.call(event, fresh_receipt)
    end
    assertions += 1

    event = deep_copy(fresh_event)
    event["artifact"]["path"] = File.join(
      vault_root, "05-Failures-and-Lessons", "GOAL-TERMINATION-FRESH", "evidence.md"
    )
    expect_method_non_pass("goal-termination-knowledge-evidence-inside-vault",
                           "does not share one exact root") do
      freshness.call(event, fresh_receipt)
    end
    assertions += 1
  end

  merge_repo = File.join(fixtures, "goal-termination-merge-parent-negative")
  FileUtils.mkdir_p(merge_repo)
  git_fixture!(merge_repo, "init", "--quiet")
  git_fixture!(merge_repo, "config", "user.name", "Goal Termination Parent Fixture")
  git_fixture!(merge_repo, "config", "user.email", "goal-parent@example.invalid")
  File.binwrite(File.join(merge_repo, "base.txt"), "base\n")
  git_fixture!(merge_repo, "add", "base.txt")
  git_fixture!(merge_repo, "commit", "--quiet", "-m", "base")
  base_commit = git_fixture!(merge_repo, "rev-parse", "HEAD")
  base_branch = git_fixture!(merge_repo, "symbolic-ref", "--short", "HEAD")
  git_fixture!(merge_repo, "checkout", "--quiet", "-b", "merge-parent-side")
  File.binwrite(File.join(merge_repo, "side.txt"), "side\n")
  git_fixture!(merge_repo, "add", "side.txt")
  git_fixture!(merge_repo, "commit", "--quiet", "-m", "side")
  git_fixture!(merge_repo, "checkout", "--quiet", base_branch)
  git_fixture!(merge_repo, "merge", "--quiet", "--no-ff", "-m", "merge", "merge-parent-side")
  merge_commit = git_fixture!(merge_repo, "rev-parse", "HEAD")
  expect_method_non_pass("goal-termination-merge-parent-rejected", "exactly one parent") do
    FounderDelegationContinuity.assert_exact_sole_parent!(
      merge_repo, merge_commit, base_commit, "Founder Goal-termination amendment candidate"
    )
  end
  assertions += 1

  exact_original_decision = {
    "path" => File.join(
      FounderDelegationContinuity::GOAL_TERMINATION_DURABLE_EVIDENCE_ROOT,
      FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_DECISION_FILENAME
    ),
    "byte_length" => FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_DECISION_BYTE_LENGTH,
    "sha256" => FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_DECISION_SHA256
  }
  exact_original_human = {
    "path" => File.join(
      FounderDelegationContinuity::GOAL_TERMINATION_DURABLE_EVIDENCE_ROOT,
      FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_HUMAN_FILENAME
    ),
    "byte_length" => FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_HUMAN_BYTE_LENGTH,
    "sha256" => FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_HUMAN_SHA256
  }
  exact_original_inventory = {
    "path" => File.join(
      FounderDelegationContinuity::GOAL_TERMINATION_DURABLE_EVIDENCE_ROOT,
      FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_INVENTORY_FILENAME
    ),
    "byte_length" => FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_INVENTORY_BYTE_LENGTH,
    "sha256" => FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_INVENTORY_SHA256
  }
  exact_amendment_proposal = {
    "path" => File.join(
      FounderDelegationContinuity::GOAL_TERMINATION_DURABLE_EVIDENCE_ROOT,
      FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_PROPOSAL_FILENAME
    ),
    "byte_length" => FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_PROPOSAL_BYTE_LENGTH,
    "sha256" => FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_PROPOSAL_SHA256
  }
  drifted_original_decision = deep_copy(exact_original_decision)
  drifted_original_decision["sha256"] = "0" * 64
  expect_method_non_pass("goal-termination-original-decision-hash-anchor", "exact identity drift") do
    FounderDelegationContinuity.validate_goal_termination_original_identity_anchors!(
      Pathname.new(FounderDelegationContinuity::GOAL_TERMINATION_DURABLE_EVIDENCE_ROOT),
      drifted_original_decision, exact_original_human, exact_original_inventory,
      exact_amendment_proposal
    )
  end
  assertions += 1

  expect_method_non_pass("goal-termination-original-authority-root-anchor",
                         "durable Evidence root identity drift") do
    FounderDelegationContinuity.validate_goal_termination_original_identity_anchors!(
      Pathname.new(File.join(fixtures, "coherent-relocated-authority-root")),
      exact_original_decision, exact_original_human, exact_original_inventory,
      exact_amendment_proposal
    )
  end
  assertions += 1

  canonical_imported_event = current_truth.fetch("founder_knowledge_sync").fetch("events")
                                          .reverse.find do |event|
    next false unless event["status"] == "IMPORTED"
    review_path = event.dig("review", "path")
    receipt_path = event.dig("receipt", "path")
    next false unless File.file?(review_path.to_s) && File.file?(receipt_path.to_s)

    begin
      JSON.parse(File.binread(review_path))["schema_version"] ==
        "founder-knowledge-review/v2" &&
        JSON.parse(File.binread(receipt_path))["schema_version"] ==
          "founder-knowledge-import-receipt/v1"
    rescue JSON::ParserError
      false
    end
  end
  raise "canonical default Knowledge v2/v1 imported fixture is missing" unless
    canonical_imported_event
  knowledge_artifact_bytes = FounderDelegationContinuity.validate_identity(
    canonical_imported_event.fetch("artifact"), "canonical Knowledge Artifact fixture"
  )
  knowledge_vault_bytes = FounderDelegationContinuity.validate_identity(
    canonical_imported_event.fetch("vault_import"), "canonical Knowledge Vault fixture"
  )
  expect_method_pass("goal-termination-canonical-knowledge-verifiers-pass") do
    FounderDelegationContinuity.validate_goal_termination_knowledge_review!(
      canonical_imported_event, canonical_imported_event.fetch("review"),
      current_truth.dig("founder_knowledge_sync", "vault_path")
    )
    FounderDelegationContinuity.validate_goal_termination_knowledge_receipt!(
      ROOT, canonical_imported_event, canonical_imported_event.fetch("receipt"),
      knowledge_artifact_bytes, knowledge_vault_bytes
    )
  end
  assertions += 1

  arbitrary_review_identity = write_bytes_identity(
    fixtures, "goal-termination-unit-arbitrary-knowledge-review.json",
    "{\"target_verdict\":\"PASS\"}\n"
  )
  expect_method_non_pass("goal-termination-canonical-knowledge-review-closed",
                         "independent Knowledge Review keys are not closed") do
    FounderDelegationContinuity.validate_goal_termination_knowledge_review!(
      canonical_imported_event, arbitrary_review_identity,
      current_truth.dig("founder_knowledge_sync", "vault_path")
    )
  end
  assertions += 1

  arbitrary_receipt_identity = write_bytes_identity(
    fixtures, "goal-termination-unit-arbitrary-knowledge-receipt.json", "{}\n"
  )
  expect_method_non_pass("goal-termination-canonical-knowledge-receipt-closed",
                         "Knowledge import receipt keys are not closed") do
    FounderDelegationContinuity.validate_goal_termination_knowledge_receipt!(
      ROOT, canonical_imported_event, arbitrary_receipt_identity,
      knowledge_artifact_bytes, knowledge_vault_bytes
    )
  end
  assertions += 1

  active_ledger = active_fixture_truth.fetch("phase_execution_envelope").fetch("task_ledger")
  terminal_ledger = terminal_fixture_truth.fetch("phase_execution_envelope").fetch("task_ledger")

  expect_method_pass("single-task-expansion-active-zero-suffix-pass") do
    prior = FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, active_ledger, active_source_route.fetch("task_plan"), terminal_source_decision
    )
    raise "ACTIVE fixture prior prefix drift" unless prior == active_ledger
  end
  assertions += 1

  expect_method_pass("single-task-expansion-terminal-one-suffix-pass") do
    prior = FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, terminal_ledger, terminal_source_route.fetch("task_plan"), terminal_source_decision
    )
    raise "terminal fixture suffix drift" unless terminal_ledger.length == prior.length + 1
  end
  assertions += 1

  expect_pass(
    fixtures,
    "frozen-single-task-expansion-terminal-one-suffix",
    terminal_fixture_truth,
    terminal_fixture_truth.dig("founder_escalation_control", "disposition")
  )
  assertions += 1

  ledger = deep_copy(terminal_ledger)
  ledger.pop
  expect_method_non_pass("single-task-expansion-terminal-suffix-required",
                         "consumed source Task requires exactly one sole new ledger suffix") do
    FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, ledger, terminal_source_route.fetch("task_plan"), terminal_source_decision
    )
  end
  assertions += 1

  ledger = deep_copy(terminal_ledger)
  ledger << deep_copy(ledger.last)
  expect_method_non_pass("single-task-expansion-duplicate-suffix-rejected",
                         "phase execution task ledger contains duplicate Task ids") do
    FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, ledger, terminal_source_route.fetch("task_plan"), terminal_source_decision
    )
  end
  assertions += 1

  ledger = deep_copy(terminal_ledger)
  extra = deep_copy(ledger.last)
  extra["task_id"] = "AIOS-P2-999_UNAUTHORIZED_SECOND_TASK"
  ledger << extra
  expect_method_non_pass("single-task-expansion-second-suffix-rejected",
                         "consumed source Task requires exactly one sole new ledger suffix") do
    FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, ledger, terminal_source_route.fetch("task_plan"), terminal_source_decision
    )
  end
  assertions += 1

  ledger = deep_copy(terminal_ledger)
  ledger.first["status"] = "TERMINAL_PREFIX_DRIFT_NON_PASS"
  expect_method_non_pass("single-task-expansion-prefix-drift-rejected",
                         "prior ledger prefix drifts from activation-parent accounting") do
    FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, ledger, terminal_source_route.fetch("task_plan"), terminal_source_decision
    )
  end
  assertions += 1

  ledger = deep_copy(active_ledger)
  ledger << deep_copy(terminal_ledger.last)
  expect_method_non_pass("single-task-expansion-active-source-cannot-be-consumed",
                         "READY or ACTIVE source Task cannot appear in the consumed ledger") do
    FounderDelegationContinuity.validate_single_task_expansion_ledger!(
      ROOT, ledger, active_source_route.fetch("task_plan"), terminal_source_decision
    )
  end
  assertions += 1

  route = deep_copy(terminal_source_route)
  route.fetch("first_task")["status"] = "ACTIVE"
  expect_method_non_pass("single-task-expansion-first-task-lifecycle-drift",
                         "first Task must exactly equal its sole Task plan entry including lifecycle") do
    FounderDelegationContinuity.validate_source_route_authority!(ROOT, route)
  end
  assertions += 1

  expect_method_pass("terminal-receipt-exact-baseline") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT,
      terminal_entry,
      terminal_contract,
      terminal_receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("candidate")["created"] = true
  expect_method_non_pass("terminal-receipt-cannot-invent-candidate",
                         "cannot claim a candidate") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("held_validation")["opened"] = true
  expect_method_non_pass("terminal-receipt-cannot-invent-held-validation",
                         "cannot claim held validation") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("independent_terminal_review")["target_verdict"] = "PASS"
  expect_method_non_pass("terminal-receipt-cannot-rewrite-independent-review",
                         "independent terminal Review binding drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("outcome")["p2_capability_progress_percent"] = 100
  expect_method_non_pass("terminal-receipt-cannot-invent-capability-progress",
                         "Phase outcome drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  contract = deep_copy(terminal_contract)
  contract.fetch("terminal_outcome")["quality_review"] = "NON_PASS"
  expect_method_non_pass("terminal-contract-candidate-quality-must-remain-not-started",
                         "Contract outcome projection drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, contract, terminal_receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  contract = deep_copy(terminal_contract)
  canonical_source = contract.fetch("dependencies").find do |dependency|
    dependency["kind"] == "CANONICAL_SOURCE"
  end
  contract.fetch("dependencies") << deep_copy(canonical_source)
  expect_method_non_pass("terminal-contract-canonical-source-must-be-unique",
                         "exactly one CANONICAL_SOURCE") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, contract, terminal_receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt["activation_parent"] = deep_copy(receipt.fetch("canonical_before_terminal_sync"))
  expect_method_non_pass("terminal-activation-parent-must-equal-contract-source",
                         "drifts from the Contract CANONICAL_SOURCE") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("canonical_before_terminal_sync")["tree"] = "0" * 40
  expect_method_non_pass("terminal-canonical-before-tree-must-be-exact",
                         "tree does not match its commit") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("canonical_before_terminal_sync")["commit"] = "f" * 40
  receipt.fetch("canonical_before_terminal_sync")["tree"] = "0" * 40
  expect_method_non_pass("terminal-canonical-before-commit-must-exist",
                         "commit does not exist") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  root_commit = `git rev-list --max-parents=0 HEAD`.lines.first.to_s.strip
  root_tree = `git rev-parse #{root_commit}^{tree}`.strip
  receipt = deep_copy(terminal_receipt)
  receipt["canonical_before_terminal_sync"] = { "commit" => root_commit, "tree" => root_tree }
  expect_method_non_pass("terminal-canonical-before-must-descend-from-activation-parent",
                         "ancestor relation does not hold") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  expect_method_non_pass("terminal-entry-introduction-anchor-must-be-exact",
                         "ledger entry introduction anchor drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, terminal_receipt,
      ledger_anchor_commit: terminal_receipt.dig("canonical_before_terminal_sync", "commit")
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("execution_accounting")["formal_dev_repeat_count"] = 999
  expect_method_non_pass("terminal-formal-dev-repeat-count-must-be-exact",
                         "execution counters drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  receipt.fetch("evidence_bindings")["formal_dev_repeat_003_matrix"] =
    write_json_identity(fixtures, "DEV_PRODUCT_MOCKMVC_MATRIX.json", {})
  expect_method_non_pass("terminal-full-inventory-matrix-projection-must-be-exact",
                         "full inventory matrix projection drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  synchronously_rebind_terminal_inventory(
    fixtures, receipt, "terminal-inventory-non-matrix-projection-drift"
  ) do |full_inventory|
    non_matrix_row = full_inventory.fetch("files").find do |row|
      row["relative_path"] != "DEV_PRODUCT_MOCKMVC_MATRIX.json"
    end
    non_matrix_row["sha256"] = "0" * 64
    full_inventory["file_projection_sha256"] =
      Digest::SHA256.hexdigest(JSON.generate(full_inventory.fetch("files")))
  end
  expect_method_non_pass("terminal-full-inventory-frozen-projection-must-be-exact",
                         "full inventory projection drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  synchronously_rebind_terminal_inventory(
    fixtures, receipt, "terminal-inventory-directory-projection-drift"
  ) do |full_inventory|
    full_inventory["directory_projection_sha256"] = "0" * 64
  end
  expect_method_non_pass("terminal-full-inventory-directory-projection-must-be-frozen",
                         "full inventory projection drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  synchronously_rebind_terminal_inventory(
    fixtures, receipt, "terminal-inventory-run-root-drift"
  ) do |full_inventory|
    full_inventory["run_root"] =
      "/private/tmp/p2-064-dev-adapter-preflight/formal-dev-repeat-003-drift"
  end
  expect_method_non_pass("terminal-full-inventory-run-root-must-be-frozen",
                         "full inventory projection drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  synchronously_rebind_terminal_inventory(
    fixtures, receipt, "terminal-inventory-non-matrix-aggregate-drift"
  ) do |full_inventory|
    non_matrix_row = full_inventory.fetch("files").find do |row|
      row["relative_path"] != "DEV_PRODUCT_MOCKMVC_MATRIX.json"
    end
    non_matrix_row["byte_length"] += 1
  end
  expect_method_non_pass("terminal-full-inventory-non-matrix-byte-sum-must-be-exact",
                         "full inventory aggregate byte sum drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  snapshots = receipt.dig("evidence_bindings", "product_dirty_snapshot_files")
  snapshots[1] = deep_copy(snapshots[0])
  expect_method_non_pass("terminal-dirty-snapshot-identities-must-be-unique",
                         "dirty snapshot identities must be unique") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  quality = JSON.parse(File.binread(
    receipt.dig("evidence_bindings", "formal_dev_repeat_003_terminal_quality_non_pass", "path")
  ))
  quality.dig("run003", "matrix")["sha256"] = "0" * 64
  quality_identity = write_json_identity(fixtures, "terminal-quality-child-drift.json", quality)
  receipt.fetch("evidence_bindings")["formal_dev_repeat_003_terminal_quality_non_pass"] =
    quality_identity
  expect_method_non_pass("terminal-quality-child-identities-must-be-exact",
                         "terminal Quality lifecycle drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  receipt = deep_copy(terminal_receipt)
  review = JSON.parse(File.binread(
    receipt.dig("evidence_bindings", "independent_terminal_task_review", "path")
  ))
  review.dig("exact_run003_bindings", "run_terminal_receipt")["sha256"] = "0" * 64
  review_identity = write_json_identity(fixtures, "terminal-review-child-drift.json", review)
  receipt.fetch("evidence_bindings")["independent_terminal_task_review"] = review_identity
  receipt.fetch("independent_terminal_review")["identity"] = deep_copy(review_identity)
  expect_method_non_pass("terminal-review-child-identities-must-be-exact",
                         "independent terminal Review lifecycle drift") do
    FounderDelegationContinuity.validate_predeclared_task_terminal_outcome!(
      ROOT, terminal_entry, terminal_contract, receipt,
      ledger_anchor_commit: terminal_anchor_commit
    )
  end
  assertions += 1

  if termination_decision && termination_final
    human_identity = deep_copy(
      current_truth.dig("founder_escalation_control", "resolution", "human_record")
    )
    amendment_identity = deep_copy(
      current_truth.dig("termination_schema_amendment", "structured_amendment")
    )
    amendment_decision = JSON.parse(File.binread(amendment_identity.fetch("path")))
    bind_amendment = lambda do |truth, name, variant: nil, raw_bytes: nil,
                               mutate_originals: false|
      evidence_root = File.join(fixtures, "#{name}-authority")
      FileUtils.mkdir_p(evidence_root)
      evidence_root = File.realpath(evidence_root)
      copy_identity = lambda do |source, filename|
        destination = File.join(evidence_root, filename)
        File.binwrite(destination, File.binread(source))
        identity_for(destination)
      end
      human_source = current_truth.dig(
        "founder_escalation_control", "resolution", "human_record", "path"
      )
      human_path = File.join(evidence_root, File.basename(human_source))
      human_bytes = File.binread(human_source)
      human_bytes += "\nCOHERENT_FULL_REBIND_NEGATIVE\n" if mutate_originals
      File.binwrite(human_path, human_bytes)
      human = identity_for(human_path)

      original_source = current_truth.dig(
        "founder_escalation_control", "resolution", "structured_decision", "path"
      )
      original_path = File.join(evidence_root, File.basename(original_source))
      original_bytes = File.binread(original_source)
      if mutate_originals
        original_value = JSON.parse(original_bytes)
        original_value.fetch("human_readable_record")["byte_length"] = human["byte_length"]
        original_value.fetch("human_readable_record")["sha256"] = human["sha256"]
        original_bytes = JSON.generate(original_value) + "\n"
      end
      File.binwrite(original_path, original_bytes)
      original = identity_for(original_path)
      original_inventory_source = amendment_decision.dig(
        "amends_decision", "closed_inventory", "path"
      )
      if mutate_originals
        original_inventory_value = JSON.parse(File.binread(original_inventory_source))
        original_inventory_value["stage_root"] = evidence_root
        rebound_originals = {
          FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_HUMAN_FILENAME => human,
          FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_DECISION_FILENAME => original
        }
        original_inventory_value.fetch("payload_entries").each do |entry|
          identity = rebound_originals.fetch(entry.fetch("relative_path"))
          entry["byte_length"] = identity["byte_length"]
          entry["sha256"] = identity["sha256"]
        end
        original_projection = original_inventory_value.fetch("payload_entries")
                                                     .sort_by { |entry| entry.fetch("relative_path").b }
                                                     .map do |entry|
          [
            entry.fetch("relative_path"), entry.fetch("byte_length"),
            entry.fetch("sha256"), entry.fetch("mode"), entry.fetch("nlink"), "false"
          ].join("\t") + "\n"
        end.join
        original_inventory_value["payload_projection"]["byte_length"] =
          original_projection.bytesize
        original_inventory_value["payload_projection"]["sha256"] =
          Digest::SHA256.hexdigest(original_projection)
        original_inventory_value["payload_totals"]["byte_length"] =
          human.fetch("byte_length") + original.fetch("byte_length")
        original_inventory_path = File.join(
          evidence_root,
          FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_INVENTORY_FILENAME
        )
        File.binwrite(
          original_inventory_path, JSON.generate(original_inventory_value) + "\n"
        )
        inventory = identity_for(original_inventory_path)
      else
        inventory = copy_identity.call(
          original_inventory_source,
          FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_INVENTORY_FILENAME
        )
      end
      proposal = copy_identity.call(
        current_truth.dig("termination_schema_amendment", "proposal", "path"),
        FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_PROPOSAL_FILENAME
      )
      bind_goal_termination_decision(truth, original, human)
      if mutate_originals
        knowledge_event = truth.fetch("founder_knowledge_sync").fetch("events").last
        knowledge_event["rationale"] = knowledge_event.fetch("rationale").sub(
          current_truth.dig(
            "founder_escalation_control", "resolution", "structured_decision", "sha256"
          ),
          original.fetch("sha256")
        )
        rehash_knowledge_event!(knowledge_event)
      end
      truth.fetch("termination_schema_amendment")["proposal"] = proposal
      bytes = raw_bytes
      if variant
        variant["durable_evidence_root"] = evidence_root
        variant.fetch("installation_contract")["durable_root"] = evidence_root
        variant.fetch("amends_decision")["human_readable_decision"] = human
        variant.fetch("amends_decision")["structured_decision"] = original
        variant.fetch("amends_decision")["closed_inventory"] = inventory
        variant["proposal"] = proposal
        bytes = recursively_sorted_json(variant) + "\n"
      end
      amendment_path = File.join(
        evidence_root,
        FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_DECISION_FILENAME
      )
      File.binwrite(amendment_path, bytes)
      final_amendment = identity_for(amendment_path)
      truth.fetch("termination_schema_amendment")["structured_amendment"] = final_amendment

      inventory_value = JSON.parse(File.binread(
        current_truth.dig("termination_schema_amendment", "amendment_inventory", "path")
      ))
      inventory_value["durable_root"] = evidence_root
      payload_identities = {
        FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_HUMAN_FILENAME => human,
        FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_DECISION_FILENAME => original,
        FounderDelegationContinuity::GOAL_TERMINATION_ORIGINAL_INVENTORY_FILENAME => inventory,
        FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_PROPOSAL_FILENAME => proposal,
        FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_DECISION_FILENAME => final_amendment
      }
      inventory_value.fetch("payload_entries").each do |entry|
        identity = payload_identities.fetch(entry.fetch("relative_path"))
        entry["byte_length"] = identity["byte_length"]
        entry["sha256"] = identity["sha256"]
      end
      projection_bytes = inventory_value.fetch("payload_entries")
                                        .sort_by { |entry| entry.fetch("relative_path").b }
                                        .map do |entry|
        [
          entry.fetch("relative_path"), entry.fetch("byte_length"),
          entry.fetch("sha256"), entry.fetch("mode"), entry.fetch("nlink"), "false"
        ].join("\t") + "\n"
      end.join
      inventory_value["payload_projection"] = {
        "byte_length" => projection_bytes.bytesize,
        "format" =>
          "RELATIVE_PATH_TAB_BYTE_LENGTH_TAB_SHA256_TAB_MODE_TAB_NLINK_TAB_SYMLINK_LF",
        "sha256" => Digest::SHA256.hexdigest(projection_bytes)
      }
      amendment_inventory_path = File.join(
        evidence_root,
        FounderDelegationContinuity::GOAL_TERMINATION_AMENDMENT_INVENTORY_FILENAME
      )
      File.binwrite(
        amendment_inventory_path, recursively_sorted_json(inventory_value) + "\n"
      )
      truth.fetch("termination_schema_amendment")["amendment_inventory"] =
        identity_for(amendment_inventory_path)
      evidence_root
    end
    bind_amendment_variant = lambda do |truth, name, variant|
      bind_amendment.call(truth, name, variant: variant)
    end
    bind_amendment_bytes = lambda do |truth, name, bytes|
      bind_amendment.call(truth, name, raw_bytes: bytes)
    end
    bind_variant = lambda do |truth, name, variant|
      identity = write_compact_json_identity(fixtures, name, variant)
      bind_goal_termination_decision(truth, identity, human_identity)
    end
    bind_bytes = lambda do |truth, name, bytes|
      identity = write_bytes_identity(fixtures, name, bytes)
      bind_goal_termination_decision(truth, identity, human_identity)
    end

    truth = deep_copy(current_truth)
    bind_amendment.call(
      truth, "goal-termination-coherent-full-authority-rebind",
      variant: deep_copy(amendment_decision), mutate_originals: true
    )
    expect_non_pass(fixtures, "goal-termination-coherent-full-authority-rebind", truth,
                    "Knowledge suffix static projection drift")
    assertions += 1

    physical_clone = File.join(fixtures, "goal-termination-physical-root-clone")
    clone_stdout, clone_stderr, clone_status = Open3.capture3(
      "git", "clone", "--quiet", "--no-hardlinks", ROOT, physical_clone,
      chdir: fixtures
    )
    raise "goal-termination physical clone failed\n#{clone_stdout}#{clone_stderr}" unless
      clone_status.success?
    clone_stdout, clone_stderr, clone_status = Open3.capture3(
      "ruby", File.join(physical_clone, "scripts", "validate-founder-delegation-continuity.rb"),
      "--fixture", File.join(physical_clone, "docs", "aios", "truth", "project_state.yaml"),
      chdir: physical_clone
    )
    raise "goal-termination physical clone unexpectedly passed" if clone_status.success?
    unless (clone_stdout + clone_stderr).include?(
      "not executing from the exact canonical physical repository root"
    )
      raise "goal-termination physical clone failed for the wrong reason\n#{clone_stdout}#{clone_stderr}"
    end
    assertions += 1

    truth = deep_copy(current_truth)
    truth.delete("termination_schema_amendment")
    expect_non_pass(fixtures, "goal-termination-amendment-binding-required", truth,
                    "terminal-schema amendment binding must be a mapping")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("termination_schema_amendment").delete("amendment_inventory")
    expect_non_pass(fixtures, "goal-termination-amendment-inventory-binding-required", truth,
                    "terminal-schema amendment binding keys are not closed")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("termination_schema_amendment", "amendment_inventory")["sha256"] = "0" * 64
    expect_non_pass(fixtures, "goal-termination-amendment-inventory-hash-exact", truth,
                    "amendment inventory SHA-256 mismatch")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("termination_schema_amendment", "authorization_token").replace(
      "AUTHORIZE_SOURCE_LENS_GOAL_TERMINATION_FIVE_PATH_TERMINAL_SCHEMA_AMENDMENT_V2"
    )
    expect_non_pass(fixtures, "goal-termination-amendment-alternate-token-rejected", truth,
                    "terminal-schema amendment is not Founder-authorized final")
    assertions += 1

    {
      "goal" => "termination_schema_amendment_ref",
      "current_phase_route" => "terminal_schema_amendment_ref",
      "active_work" => "termination_schema_amendment_ref"
    }.each do |root_key, field|
      truth = deep_copy(current_truth)
      truth.fetch(root_key)[field] = "alternate_amendment"
      expect_non_pass(fixtures, "goal-termination-amendment-ref-#{root_key}", truth,
                      "amendment")
      assertions += 1
    end

    truth = deep_copy(current_truth)
    truth.dig("founder_escalation_control", "resolution")["terminal_schema_amendment_ref"] =
      "alternate_amendment"
    expect_non_pass(fixtures, "goal-termination-amendment-ref-control", truth,
                    "control amendment reference drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("termination_schema_amendment", "structured_amendment")["path"] =
      File.join(fixtures, "missing-amendment.json")
    expect_non_pass(fixtures, "goal-termination-amendment-file-required", truth,
                    "structured amendment durable path drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("termination_schema_amendment", "structured_amendment")["sha256"] = "0" * 64
    expect_non_pass(fixtures, "goal-termination-amendment-hash-exact", truth,
                    "structured terminal-schema amendment SHA-256 mismatch")
    assertions += 1

    truth = deep_copy(current_truth)
    authority_root = bind_amendment_bytes.call(
      truth, "goal-termination-amendment-invalid-json.json", "{invalid}\n"
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-json-valid", truth, authority_root,
      "structured terminal-schema amendment JSON is invalid"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("authority")["exact_token"] =
      "AUTHORIZE_SOURCE_LENS_GOAL_TERMINATION_FIVE_PATH_TERMINAL_SCHEMA_AMENDMENT_V2"
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-authority-token.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-authority-token-exact", truth, authority_root,
      "amendment exact authorization drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("scope")["sixth_path_authorized"] = true
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-sixth-path.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-sixth-path-rejected", truth, authority_root,
      "amendment five-path scope drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("scope").fetch("canonical_paths") << "scripts/sixth-path.rb"
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-path-allowlist.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-exact-five-paths", truth, authority_root,
      "amendment five-path scope drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.dig("precedence", "narrow_supersession", "exact_original_field_paths") <<
      "authorized_minimal_sync_scope.maximum_commits"
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-precedence-broadened.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-precedence-exact-two-fields", truth, authority_root,
      "supersession field boundary drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.dig("precedence", "narrow_supersession", "applies_only_to_bound_commit")
           .fetch("canonical_paths") << "scripts/sixth-path.rb"
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-precedence-sixth-path.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-precedence-five-path-only", truth, authority_root,
      "bound-commit precedence drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.dig("precedence", "narrow_supersession", "fail_closed_precedence")
           .store("outside_bound_commit", "AMENDMENT_CONTINUES")
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-precedence-outside-bound.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-precedence-outside-bound-fail-closed", truth,
      authority_root, "fail-closed precedence drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("installation_contract")["exact_file_count"] = 5
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-install-partial.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-install-six-files", truth, authority_root,
      "installation boundary drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("required_validation")["results_claimed"] = true
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-false-validation-result.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-no-preclaimed-results", truth, authority_root,
      "required-validation drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("terminal_schema_delta")["next_engineering_action"] = "NONE"
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-next-action.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-next-action-exact", truth, authority_root,
      "amendment terminal-schema projection drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(amendment_decision)
    variant.fetch("external_effects")["network"] = true
    authority_root = bind_amendment_variant.call(
      truth, "goal-termination-amendment-effect.json", variant
    )
    expect_non_pass_with_durable_evidence_root(
      fixtures, "goal-termination-amendment-effects-false", truth, authority_root,
      "amendment external effect drift"
    )
    assertions += 1

    truth = deep_copy(current_truth)
    truth["goal"]["termination_decision"] = nil
    expect_non_pass(fixtures, "goal-termination-decision-identity-required", truth,
                    "decision cross-binding[1] must be a mapping")
    assertions += 1

    truth = deep_copy(current_truth)
    missing_identity = deep_copy(truth.dig("current_phase_route", "founder_decision"))
    missing_identity["path"] = File.join(fixtures, "missing-termination-decision.json")
    bind_goal_termination_decision(truth, missing_identity, human_identity)
    expect_non_pass(fixtures, "goal-termination-decision-file-required", truth,
                    "structured decision is unavailable")
    assertions += 1

    truth = deep_copy(current_truth)
    relative_identity = deep_copy(truth.dig("current_phase_route", "founder_decision"))
    relative_identity["path"] = "relative-termination-decision.json"
    bind_goal_termination_decision(truth, relative_identity, human_identity)
    expect_non_pass(fixtures, "goal-termination-decision-path-absolute", truth,
                    "path must be absolute")
    assertions += 1

    truth = deep_copy(current_truth)
    bad_hash = deep_copy(truth.dig("current_phase_route", "founder_decision"))
    bad_hash["sha256"] = "0" * 64
    bind_goal_termination_decision(truth, bad_hash, human_identity)
    expect_non_pass(fixtures, "goal-termination-decision-hash-exact", truth,
                    "structured decision SHA-256 mismatch")
    assertions += 1

    original_bytes = JSON.generate(termination_decision) + "\n"
    truth = deep_copy(current_truth)
    duplicate_bytes = "{\"schema_version\":\"duplicate\"," + original_bytes.delete_prefix("{")
    bind_bytes.call(truth, "goal-termination-duplicate-key.json", duplicate_bytes)
    expect_non_pass(fixtures, "goal-termination-duplicate-json-key", truth,
                    "contains duplicate JSON key")
    assertions += 1

    truth = deep_copy(current_truth)
    bind_bytes.call(truth, "goal-termination-invalid-json.json", "{invalid}\n")
    expect_non_pass(fixtures, "goal-termination-invalid-json", truth,
                    "JSON is invalid")
    assertions += 1

    truth = deep_copy(current_truth)
    bind_bytes.call(truth, "goal-termination-invalid-utf8.json", "{\"x\":\"\xFF\"}\n".b)
    expect_non_pass(fixtures, "goal-termination-invalid-utf8", truth,
                    "encoding is invalid")
    assertions += 1

    truth = deep_copy(current_truth)
    bind_bytes.call(truth, "goal-termination-noncompact.json",
                    JSON.pretty_generate(termination_decision) + "\n")
    expect_non_pass(fixtures, "goal-termination-json-must-be-compact", truth,
                    "serialization drift")
    assertions += 1

    truth = deep_copy(current_truth)
    bind_bytes.call(truth, "goal-termination-final-lf-required.json",
                    JSON.generate(termination_decision))
    expect_non_pass(fixtures, "goal-termination-json-final-lf-required", truth,
                    "serialization drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant["unexpected"] = true
    bind_variant.call(truth, "goal-termination-extra-root-key.json", variant)
    expect_non_pass(fixtures, "goal-termination-root-object-closed", truth,
                    "structured decision keys are not closed")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.fetch("decision")["unexpected"] = true
    bind_variant.call(truth, "goal-termination-extra-nested-key.json", variant)
    expect_non_pass(fixtures, "goal-termination-nested-object-closed", truth,
                    "outcome keys are not closed")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.fetch("authorization")["exact_token"] =
      "AUTHORIZE_SOURCE_LENS_CURRENT_LONG_TERM_GOAL_TERMINATION_AFTER_P2_RESEARCH_NON_PASS_V2"
    bind_variant.call(truth, "goal-termination-alternate-token.json", variant)
    expect_non_pass(fixtures, "goal-termination-alternate-token-rejected", truth,
                    "exact authorization drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant["schema_version"] = "founder-long-term-goal-termination-decision/v2"
    bind_variant.call(truth, "goal-termination-wrong-schema.json", variant)
    expect_non_pass(fixtures, "goal-termination-schema-exact", truth,
                    "structured decision identity drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.fetch("human_readable_record")["sha256"] = "0" * 64
    bind_variant.call(truth, "goal-termination-human-binding-drift.json", variant)
    expect_non_pass(fixtures, "goal-termination-human-record-exact", truth,
                    "human record binding drift")
    assertions += 1

    {
      "repository-path" => ["path", "/private/tmp/not-canonical"],
      "repository-branch" => ["branch", "not-main"],
      "repository-clean-state" => ["workspace_status", "DIRTY"]
    }.each do |name, (key, value)|
      truth = deep_copy(current_truth)
      variant = deep_copy(termination_decision)
      variant.dig("binding", "canonical_repository")[key] = value
      bind_variant.call(truth, "goal-termination-#{name}.json", variant)
      expected_fragment = key == "workspace_status" ?
        "canonical repository clean-state drift" : "canonical repository projection drift"
      expect_non_pass(fixtures, "goal-termination-#{name}-exact", truth,
                      expected_fragment)
      assertions += 1
    end

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.dig("binding", "canonical_repository")["tree"] = "0" * 40
    bind_variant.call(truth, "goal-termination-parent-tree-drift.json", variant)
    expect_non_pass(fixtures, "goal-termination-parent-tree-exact", truth,
                    "tree does not match its commit")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.dig("binding", "truth")["sha256"] = "0" * 64
    bind_variant.call(truth, "goal-termination-parent-truth-drift.json", variant)
    expect_non_pass(fixtures, "goal-termination-parent-truth-exact", truth,
                    "parent Truth identity drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.dig("binding", "long_term_goal")["canonical_sha256"] = "0" * 64
    bind_variant.call(truth, "goal-termination-goal-binding-drift.json", variant)
    expect_non_pass(fixtures, "goal-termination-goal-binding-exact", truth,
                    "Long-term Goal identity drift")
    assertions += 1

    {
      "constitution" => "strategic_constitution",
      "evaluation" => "evaluation_protocol"
    }.each do |name, key|
      truth = deep_copy(current_truth)
      variant = deep_copy(termination_decision)
      variant.dig("binding", key)["sha256"] = "0" * 64
      bind_variant.call(truth, "goal-termination-#{name}-binding-drift.json", variant)
      expect_non_pass(fixtures, "goal-termination-#{name}-binding-exact", truth,
                      "#{key} SHA-256 mismatch")
      assertions += 1
    end

    truth = deep_copy(current_truth)
    variant = deep_copy(termination_decision)
    variant.fetch("external_effects")["network"] = true
    bind_variant.call(truth, "goal-termination-decision-effect.json", variant)
    expect_non_pass(fixtures, "goal-termination-decision-effects-false", truth,
                    "external effect drift")
    assertions += 1

    {
      "mission-achievement" => ["mission_achievement_claimed", true],
      "p2-complete" => ["p2_complete", true],
      "p2-capability-credit" => ["p2_capability_credit", 1],
      "p3-entry" => ["p3_entry_authorized", true],
      "replacement-goal" => ["replacement_goal_created", true]
    }.each do |name, (key, value)|
      truth = deep_copy(current_truth)
      variant = deep_copy(termination_decision)
      variant.fetch("decision")[key] = value
      bind_variant.call(truth, "goal-termination-#{name}.json", variant)
      expect_non_pass(fixtures, "goal-termination-#{name}-rejected", truth,
                      "outcome drift")
      assertions += 1
    end

    truth = deep_copy(current_truth)
    truth.fetch("goal")["control_plane_status_observed"] = "ACTIVE"
    expect_non_pass(fixtures, "goal-termination-cannot-leave-goal-active", truth,
                    "current Goal or P2 projection drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("goal")["current_task_authority"] = "AIOS-P2-999_FAKE_TASK"
    expect_non_pass(fixtures, "goal-termination-cannot-retain-task-authority", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("project")["p2_execution_status"] = "COMPLETE"
    expect_non_pass(fixtures, "goal-termination-cannot-complete-p2", truth,
                    "current Goal or P2 projection drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("project")["p2_accepted_capability_credit"] = 1
    expect_non_pass(fixtures, "goal-termination-cannot-invent-p2-credit", truth,
                    "P2 capability credit drift")
    assertions += 1

    truth = deep_copy(current_truth)
    required_item = truth.dig(
      "strict_phase_gate_ledger", "phases", "P2", "required_items",
      "CONTEXT_BENCHMARK_BEATS_SIMPLE_RETRIEVAL_BASELINES"
    )
    required_item["status"] = "ACCEPTED"
    expect_non_pass(fixtures, "goal-termination-exit-item-remains-missing", truth,
                    "strict Phase complete items require Exit Gate ready or complete status")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("phase_execution_envelope", "remaining")["engineering_tasks"] = 1
    expect_non_pass(fixtures, "goal-termination-envelope-remains-exhausted", truth,
                    "phase execution envelope remaining accounting drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("phase_execution_envelope")["reserved"] = {
      "task_id" => "AIOS-P2-999_FAKE_TASK"
    }
    expect_non_pass(fixtures, "goal-termination-envelope-remains-unreserved", truth,
                    "phase execution reserved Task keys are not closed")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("phase_execution_envelope").fetch("task_ledger") <<
      deep_copy(truth.fetch("phase_execution_envelope").fetch("task_ledger").last)
    expect_non_pass(fixtures, "goal-termination-no-tenth-ledger-entry", truth,
                    "phase execution task ledger contains duplicate Task ids")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("project")["current_phase"] = "P3"
    expect_non_pass(fixtures, "goal-termination-cannot-enter-p3", truth,
                    "Phase delegation status drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("active_work")["current_task"] = "AIOS-P2-999_FAKE_TASK"
    expect_non_pass(fixtures, "goal-termination-current-task-none", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    {
      "contract" => ["current_task_contract_sha256", "0" * 64],
      "branch" => ["task_branch", "codex/fake"],
      "worktree" => ["task_worktree", "/private/tmp/fake"],
      "evidence" => ["execution_evidence_root", "/private/tmp/fake-evidence"]
    }.each do |name, (key, value)|
      truth = deep_copy(current_truth)
      truth.fetch("active_work")[key] = value
      expect_non_pass(fixtures, "goal-termination-active-#{name}-null", truth,
                      "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
      assertions += 1
    end

    truth = deep_copy(current_truth)
    truth.fetch("active_work")["allowlisted_paths"] = ["src/fake"]
    expect_non_pass(fixtures, "goal-termination-active-allowlist-empty", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.dig("active_work", "budget")["engineering_hours"] = 1
    expect_non_pass(fixtures, "goal-termination-active-budget-zero", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("active_work")["founder_decision_required"] = true
    expect_non_pass(fixtures, "goal-termination-no-founder-prompt", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("current_phase_route")["next_eligible_action"] =
      "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
    expect_non_pass(fixtures, "goal-termination-route-no-next-action", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("active_work")["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
    expect_non_pass(fixtures, "goal-termination-active-no-next-action", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("current_phase_route")["additional_write_roots"] = ["/private/tmp/fake"]
    expect_non_pass(fixtures, "goal-termination-no-additional-write-root", truth,
                    "whole-Truth terminal delta drifts from the exact parent plus authorized projection")
    assertions += 1

    %w[current_phase_route active_work phase_execution_envelope].each do |root_key|
      truth = deep_copy(current_truth)
      truth.dig(root_key, "external_effects")["network"] = true
      expected_fragment = root_key == "phase_execution_envelope" ?
        "phase execution envelope external effects exceed offline boundary" :
        "whole-Truth terminal delta drifts from the exact parent plus authorized projection"
      expect_non_pass(fixtures, "goal-termination-#{root_key}-effects-false", truth,
                      expected_fragment)
      assertions += 1
    end

    truth = deep_copy(current_truth)
    truth.fetch("founder_knowledge_sync").fetch("events").pop
    expect_non_pass(fixtures, "goal-termination-knowledge-event-required", truth,
                    "requires exactly one Knowledge event suffix")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("founder_knowledge_sync")["latest_event_id"] =
      "FKS-20260809-P2-064-TERMINAL-P2-ENVELOPE-EXHAUSTED-V1"
    expect_non_pass(fixtures, "goal-termination-knowledge-latest-exact", truth,
                    "Knowledge latest-event projection drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth.fetch("founder_knowledge_sync").fetch("events").last["engineering_blocking"] = true
    expect_non_pass(fixtures, "goal-termination-knowledge-nonblocking", truth,
                    "Knowledge suffix static projection drift")
    assertions += 1

    truth = deep_copy(current_truth)
    event = truth.fetch("founder_knowledge_sync").fetch("events").last
    event["status"] = "PENDING_REVIEW"
    %w[artifact review vault_import receipt].each do |key|
      event[key] = {"path" => nil, "byte_length" => nil, "sha256" => nil}
    end
    rehash_knowledge_event!(event)
    expect_non_pass(fixtures, "goal-termination-knowledge-pending-review-null-identities", truth,
                    "Knowledge suffix lifecycle drift")
    assertions += 1

    truth = deep_copy(current_truth)
    event = truth.fetch("founder_knowledge_sync").fetch("events").last
    event["status"] = "REVIEWED_PASS_PENDING_IMPORT"
    %w[artifact review vault_import receipt].each do |key|
      event[key] = {"path" => nil, "byte_length" => nil, "sha256" => nil}
    end
    rehash_knowledge_event!(event)
    expect_non_pass(fixtures, "goal-termination-knowledge-reviewed-null-identities", truth,
                    "Knowledge suffix lifecycle drift")
    assertions += 1

    truth = deep_copy(current_truth)
    event = truth.fetch("founder_knowledge_sync").fetch("events").last
    event.fetch("receipt")["path"] = nil
    event.fetch("receipt")["byte_length"] = nil
    event.fetch("receipt")["sha256"] = nil
    rehash_knowledge_event!(event)
    expect_non_pass(fixtures, "goal-termination-knowledge-import-identities-complete", truth,
                    "Knowledge suffix lifecycle drift")
    assertions += 1

    truth = deep_copy(current_truth)
    event = truth.fetch("founder_knowledge_sync").fetch("events").last
    arbitrary_review = write_bytes_identity(
      fixtures, "goal-termination-arbitrary-knowledge-review.json",
      "{\"target_verdict\":\"PASS\"}\n"
    )
    receipt = JSON.parse(File.binread(event.dig("receipt", "path")))
    event["review"] = arbitrary_review
    receipt["review"] = arbitrary_review.merge("verdict" => "PASS")
    event["receipt"] = write_canonical_json_identity(
      fixtures, "goal-termination-rebound-arbitrary-review-receipt.json", receipt
    )
    rehash_knowledge_event!(event)
    expect_non_pass(fixtures, "goal-termination-arbitrary-knowledge-review-rejected", truth,
                    "independent Knowledge Review keys are not closed")
    assertions += 1

    truth = deep_copy(current_truth)
    event = truth.fetch("founder_knowledge_sync").fetch("events").last
    event["receipt"] = write_bytes_identity(
      fixtures, "goal-termination-arbitrary-knowledge-import-receipt.json", "{}\n"
    )
    rehash_knowledge_event!(event)
    expect_non_pass(fixtures, "goal-termination-arbitrary-knowledge-receipt-rejected", truth,
                    "Knowledge import receipt keys are not closed")
    assertions += 1
  end

  if current_truth.dig("current_phase_route", "schema_version") ==
     FounderDelegationContinuity::STRATEGIC_HOLD_ROUTE_SCHEMA
    decision_path = current_truth.dig(
      "founder_escalation_control", "resolution", "structured_decision", "path"
    )
    decision = JSON.parse(File.binread(decision_path))

    truth = deep_copy(current_truth)
    variant = deep_copy(decision)
    variant["decision"]["p3_entry_authorized"] = true
    bind_strategic_decision(
      truth, write_json_identity(fixtures, "strategic-hold-p3-entry.json", variant)
    )
    expect_non_pass(fixtures, "strategic-hold-cannot-enter-p3", truth,
                    "Founder strategic-hold disposition drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(decision)
    variant["phase_envelope"]["limits"]["engineering_tasks"] = 6
    bind_strategic_decision(
      truth, write_json_identity(fixtures, "strategic-hold-envelope-expansion.json", variant)
    )
    expect_non_pass(fixtures, "strategic-hold-cannot-expand-envelope", truth,
                    "Founder strategic-hold Phase envelope drift")
    assertions += 1

    truth = deep_copy(current_truth)
    variant = deep_copy(decision)
    variant["phase_exit_gate"]["missing_required_item_status"] = "ACCEPTED"
    bind_strategic_decision(
      truth, write_json_identity(fixtures, "strategic-hold-false-exit.json", variant)
    )
    expect_non_pass(fixtures, "strategic-hold-cannot-complete-exit-gate", truth,
                    "Founder strategic-hold Phase Exit Gate drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth["founder_escalation_control"]["founder_decision_required"] = true
    expect_non_pass(fixtures, "strategic-hold-cannot-repeat-founder-prompt", truth,
                    "Founder strategic-hold control projection drift")
    assertions += 1

    truth = deep_copy(current_truth)
    truth["active_work"]["next_eligible_action"] = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK"
    expect_non_pass(fixtures, "strategic-hold-cannot-schedule-engineering", truth,
                    "active_work Founder strategic-hold projection drift")
    assertions += 1
  end

  truth = deep_copy(reserved_base)
  trigger = JSON.parse(File.binread(
    truth.dig("founder_escalation_control", "reserved_trigger", "evidence", "path")
  ))
  trigger["condition"]["requested_budget"] = {
    "engineering_tasks" => 6,
    "engineering_hours" => 136,
    "calendar_days" => 34
  }
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "agent-invented-next-budget.json", trigger)
  expect_non_pass(fixtures, "exhausted-phase-cannot-invent-next-founder-budget", truth,
                  "exhausted Phase decision Evidence must not invent a new Founder budget")
  assertions += 1

  truth = deep_copy(reserved_base)
  trigger = JSON.parse(File.binread(
    truth.dig("founder_escalation_control", "reserved_trigger", "evidence", "path")
  ))
  trigger["supporting_evidence"].pop
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "missing-terminal-ledger-support.json", trigger)
  expect_non_pass(fixtures, "exhausted-phase-must-bind-all-terminal-receipts", truth,
                  "Founder budget expansion trigger must bind every consumed Task outcome receipt")
  assertions += 1

  truth = deep_copy(current_truth)
  terminal_entry = truth.fetch("phase_execution_envelope").fetch("task_ledger").last
  terminal_entry["outcome_receipt"] = write_json_identity(
    fixtures,
    "superficial-predeclared-terminal-receipt.json",
    {
      "task_id" => terminal_entry["task_id"],
      "route_id" => terminal_entry["route_id"],
      "status" => terminal_entry["status"]
    }
  )
  expect_non_pass(fixtures, "predeclared-terminal-receipt-substitution", truth,
                  "phase execution source Task ledger entry has no immutable Git introduction")
  assertions += 1

  expect_pass(fixtures, "ordinary-terminal-continues", base,
              "NO_RESERVED_TRIGGER_CONTINUE_PHASE")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["founder_decision_required"] = true
  expect_non_pass(fixtures, "review-non-pass-founder-required", truth,
                  "delegated independent Task must not invent a Founder authorization or action")
  assertions += 1

  truth = deep_copy(base)
  truth["current_phase_route"]["founder_phase_route_decision_required"] = true
  expect_non_pass(fixtures, "route-terminal-founder-required", truth,
                  "delegated independent Task route cannot require Founder decision")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["next_eligible_action"] = "FOUNDER_P2_PHASE_GATE"
  expect_non_pass(fixtures, "ordinary-terminal-next-founder", truth,
                  "delegated independent Task ACTIVE active_work drift")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["reserved_trigger"]["category"] =
    "FINAL_REVIEW_TARGET_NON_PASS"
  expect_non_pass(fixtures, "review-verdict-as-reserved-trigger", truth,
                  "unknown Founder reserved trigger")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["source_event"]["task_id"] =
    "AIOS-P2-999_FAKE_TASK"
  expect_non_pass(fixtures, "terminal-task-identity-drift", truth,
                  "ordinary terminal event Task identity drift")
  assertions += 1

  truth = deep_copy(base)
  truth["founder_escalation_control"]["unexpected"] = true
  expect_non_pass(fixtures, "escalation-extra-field", truth,
                  "founder_escalation_control keys are not closed")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_execution_envelope"]["remaining"]["engineering_hours"] += 1
  expect_non_pass(fixtures, "remaining-budget-drift", truth,
                  "phase execution envelope remaining accounting drift")
  assertions += 1

  truth = deep_copy(base)
  source_entry = truth.dig("phase_execution_envelope", "task_ledger", 0)
  source_entry["outcome_receipt"] = write_json_identity(
    fixtures,
    "superficial-source-terminal-receipt.json",
    {
      "schema_version" => "superficial-terminal-receipt/v1",
      "task_id" => source_entry["task_id"],
      "route_id" => source_entry["route_id"],
      "terminal_status" => source_entry["status"]
    }
  )
  expect_non_pass(fixtures, "source-terminal-receipt-substitution", truth,
                  "source Task ledger drifts from its first canonical anchor")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_execution_envelope"]["status"] = "EXHAUSTED"
  expect_non_pass(fixtures, "false-envelope-exhaustion", truth,
                  "phase execution envelope status does not match reservation and remaining capacity")
  assertions += 1

  truth = deep_copy(base)
  truth["authority"]["founder_delegation_policy"]["version"] = "1.7"
  expect_non_pass(fixtures, "policy-downgrade", truth,
                  "Founder delegation policy version drift")
  assertions += 1

  truth = deep_copy(base)
  truth["project"]["current_route_execution_status"] = "STOPPED_AT_FOUNDER_P2_PHASE_GATE"
  expect_non_pass(fixtures, "project-stopped-at-false-founder-gate", truth,
                  "delegated independent Task ACTIVE project or Goal projection drift")
  assertions += 1

  truth = deep_copy(base)
  truth["active_work"]["current_task"] = "AIOS-P2-999_FAKE_TASK"
  expect_non_pass(fixtures, "active-task-during-selection-hold", truth,
                  "delegated independent Task ACTIVE active_work drift")
  assertions += 1

  truth = deep_copy(base)
  p2 = truth.dig("strict_phase_gate_ledger", "phases", "P2")
  p2["required_items"].each_value { |item| item["status"] = "ACCEPTED" }
  p2["status"] = "EXIT_GATE_READY"
  p2["founder_phase_gate"]["status"] = "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  control = truth["founder_escalation_control"]
  control["disposition"] = "FOUNDER_DECISION_REQUIRED"
  control["reserved_trigger"] = {"category" => "PHASE_ENTRY_OR_EXIT", "evidence" => nil}
  control["source_event"] = {
    "kind" => "PHASE_EXIT_GATE_ELIGIBLE",
    "task_id" => nil,
    "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  }
  control["phase_gate_status"] = "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  control["founder_decision_required"] = true
  control["next_action_owner"] = "HUMAN_FOUNDER"
  control["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  route = truth["current_phase_route"]
  route["schema_version"] = "founder-reserved-decision-hold/v1"
  route["route_id"] = "P2_FOUNDER_RESERVED_DECISION_HOLD"
  route["status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  route["execution_status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  route["scheduling_status"] = "STOPPED_AT_FOUNDER_RESERVED_DECISION"
  route["founder_phase_route_decision_required"] = true
  route["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  route.delete("source_authority_route_ref")
  route.delete("preceding_terminal_route_ref")
  route.delete("selected_task")
  route["historical_terminal_route_ref"] = "historical_p2_057_phase_route"
  route["inherited_worktree_inventory_source"] = "historical_p2_057_phase_route"
  truth["project"]["phase_execution_status"] = "STOPPED_AT_FOUNDER_RESERVED_DECISION"
  truth["project"]["current_route_execution_status"] = "FOUNDER_RESERVED_DECISION_REQUIRED"
  active = truth["active_work"]
  active["current_task"] = "NONE"
  active["current_task_status"] = "NONE"
  active["task_resource_state"] = "NO_ACTIVE_TASK_FOUNDER_RESERVED_DECISION_HOLD"
  active["founder_decision_required"] = true
  active["founder_decision_required_scope"] = "PHASE_ENTRY_OR_EXIT"
  active["escalation_reason"] = "PHASE_ENTRY_OR_EXIT"
  active["user_action_required"] = "FOUNDER_RESERVED_DECISION"
  active["phase_route_decision_required"] = true
  active["phase_route_user_action_required"] = "FOUNDER_RESERVED_DECISION"
  active["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_pass(fixtures, "eligible-phase-exit-founder-decision", truth,
              "FOUNDER_DECISION_REQUIRED")
  assertions += 1

  truth = deep_copy(base)
  control = truth["founder_escalation_control"]
  control["disposition"] = "FOUNDER_DECISION_REQUIRED"
  control["reserved_trigger"] = {"category" => "PHASE_ENTRY_OR_EXIT", "evidence" => nil}
  control["source_event"] = {
    "kind" => "PHASE_EXIT_GATE_ELIGIBLE",
    "task_id" => nil,
    "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION"
  }
  control["founder_decision_required"] = true
  control["next_action_owner"] = "HUMAN_FOUNDER"
  control["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_non_pass(fixtures, "incomplete-phase-false-exit-gate", truth,
                  "Phase exit escalation requires a complete eligible Exit Gate")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_execution_envelope"]["external_effects"]["network"] = true
  expect_non_pass(fixtures, "silent-effect-expansion", truth,
                  "phase execution envelope external effects exceed offline boundary")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_delegation"]["anti_loop"]["reviewer_non_pass_may_trigger_founder_gate"] = true
  expect_non_pass(fixtures, "delegation-reviewer-escalation-downgrade", truth,
                  "Phase delegation anti-loop control drift")
  assertions += 1

  truth = deep_copy(base)
  truth["phase_delegation"]["agent_delegated_decisions"].delete(
    "choose_the_next_independent_phase_local_task_after_task_completion_or_stop"
  )
  expect_non_pass(fixtures, "delegated-continuation-deleted", truth,
                  "Agent delegated decision set drift")
  assertions += 1

  truth = deep_copy(base)
  historical = truth.delete("historical_p2_058_founder_expansion_phase_route")
  truth["historical_p2_058_archive_phase_route"] = historical
  truth["current_phase_route"]["source_authority_route_ref"] =
    "historical_p2_058_archive_phase_route"
  truth["phase_execution_envelope"]["authority_basis"]["source_route_ref"] =
    "historical_p2_058_archive_phase_route"
  expect_pass(fixtures, "data-driven-historical-route-reference", truth,
              "NO_RESERVED_TRIGGER_CONTINUE_PHASE")
  assertions += 1

  truth = deep_copy(base)
  truth["current_phase_route"]["schema_version"] = "1.1"
  truth["current_phase_route"]["route_id"] = "P2_FUTURE_PHASE_LOCAL_ENGINEERING_ROUTE_V1"
  truth["current_phase_route"]["founder_phase_route_decision_required"] = false
  truth["active_work"]["current_task"] = "AIOS-P2-999_FUTURE_INDEPENDENT_TASK"
  truth["active_work"]["current_task_status"] = "ACTIVE"
  truth["active_work"]["next_eligible_action"] = "COMPLETE_CURRENT_TASK_GATE"
  expect_non_pass(fixtures, "future-active-task-cannot-bypass-phase-ledger", truth,
                  "active Phase delegation envelope requires a closed delegated Route schema")
  assertions += 1

  truth["active_work"]["founder_decision_required"] = true
  expect_non_pass(fixtures, "future-active-task-cannot-self-escalate", truth,
                  "active Phase delegation envelope requires a closed delegated Route schema")
  assertions += 1

  truth = deep_copy(base)
  truth.delete("phase_execution_envelope")
  truth["current_phase_route"]["schema_version"] = "1.1"
  truth["current_phase_route"]["route_id"] = "P2_PHASE_ENVELOPE_DELETION_ESCAPE"
  expect_non_pass(fixtures, "phase-envelope-cannot-be-deleted-to-escape-delegation", truth,
                  "active Phase delegation requires a phase execution envelope")
  assertions += 1

  truth = deep_copy(base)
  support_path = File.join(fixtures, "ordinary-terminal-support.txt")
  File.binwrite(support_path, "ordinary terminal is not a reserved trigger\n")
  fake_trigger = {
    "schema_version" => "founder-reserved-trigger-evidence/v1",
    "category" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE",
    "phase" => "P2",
    "source_event" => truth["founder_escalation_control"]["source_event"],
    "source_route_id" => truth["historical_p2_055_phase_route"]["route_id"],
    "condition" => {
      "phase_route_change" => false,
      "material_scope_or_permission_expansion" => false,
      "requested_budget" => {
        "engineering_tasks" => 2,
        "engineering_hours" => 40,
        "calendar_days" => 10
      },
      "requested_external_effects" => {
        "network" => false,
        "provider" => false,
        "secret" => false,
        "remote" => false,
        "production" => false,
        "public" => false
      },
      "irreversible_asset_action" => false,
      "material_legal_privacy_commercial_commitment" => false,
      "critical_residual_risk_acceptance" => true
    },
    "supporting_evidence" => [identity_for(support_path)]
  }
  truth["founder_escalation_control"]["disposition"] = "FOUNDER_DECISION_REQUIRED"
  truth["founder_escalation_control"]["source_event"] = {
    "kind" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE_REQUIRED",
    "task_id" => nil,
    "status" => "PENDING_FOUNDER_RESERVED_DECISION"
  }
  fake_trigger["source_event"] = truth["founder_escalation_control"]["source_event"]
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "fake-critical-trigger-consistent.json", fake_trigger)
  truth["founder_escalation_control"]["reserved_trigger"] = {
    "category" => "CRITICAL_RESIDUAL_RISK_ACCEPTANCE",
    "evidence" => truth["founder_escalation_control"]["reserved_trigger"]["evidence"]
  }
  truth["founder_escalation_control"]["founder_decision_required"] = true
  truth["founder_escalation_control"]["next_action_owner"] = "HUMAN_FOUNDER"
  truth["founder_escalation_control"]["next_eligible_action"] = "FOUNDER_RESERVED_DECISION"
  expect_non_pass(fixtures, "ordinary-terminal-cannot-masquerade-as-critical-risk", truth,
                  "terminal transition only supports mechanically derived Phase exit or envelope expansion")
  assertions += 1

  truth = deep_copy(base)
  historical = truth["historical_p2_055_phase_route"]
  classifier_control = deep_copy(truth["founder_escalation_control"])
  historical["first_task"]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
  historical["task_plan"][0]["status"] = "MASTER_TASK_GATE_ACCEPTED_COMPLETE"
  historical["task_plan"][1]["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  classifier_control["source_event"] = {
    "kind" => "TASK_TERMINAL_FINAL_REVIEW_NON_PASS",
    "task_id" => historical["task_plan"][1]["task_id"],
    "status" => "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  }
  truth["founder_escalation_control"] = classifier_control
  FounderDelegationContinuity.validate_control!(
    truth,
    "P2",
    "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
    false,
    historical,
    truth["phase_execution_envelope"]
  ).tap do |result|
    raise "later Task terminal classifier drift" unless result["source_event"]["task_id"] ==
                                                        historical["task_plan"][1]["task_id"]
  end
  assertions += 1

  truth = deep_copy(base)
  truth["historical_p2_058_founder_expansion_phase_route"]["envelope"]["max_engineering_tasks"] = 4
  truth["phase_execution_envelope"]["limits"]["engineering_tasks"] = 4
  truth["phase_execution_envelope"]["remaining"]["engineering_tasks"] = 1
  expect_non_pass(fixtures, "self-consistent-source-envelope-expansion", truth,
                  "historical source Route static authority drifts from its first canonical Git anchor")
  assertions += 1

  truth = deep_copy(base)
  historical = truth["historical_p2_058_founder_expansion_phase_route"]
  historical["task_plan"][2]["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  historical["execution_status"] = "TERMINAL_FINAL_QUALITY_TARGET_NON_PASS"
  envelope = truth["phase_execution_envelope"]
  envelope["status"] = "EXHAUSTED"
  envelope["consumed"] = {
    "engineering_tasks" => 3,
    "engineering_hours" => 64,
    "calendar_days" => 16
  }
  envelope["reserved"] = nil
  envelope["remaining"] = {
    "engineering_tasks" => 0,
    "engineering_hours" => 0,
    "calendar_days" => 0
  }
  expect_non_pass(fixtures, "self-reported-unbound-second-task-cannot-exhaust-envelope", truth,
                  "phase execution task ledger omits a consumed source Route Task")
  assertions += 1

  puts "FOUNDER_DELEGATION_CONTINUITY_TESTS: PASS assertions=#{assertions}"
end

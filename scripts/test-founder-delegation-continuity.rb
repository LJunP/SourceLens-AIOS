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

def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def run_fixture(root, name, truth)
  path = File.join(root, "#{name}.yaml")
  File.binwrite(path, YAML.dump(truth))
  Open3.capture3("ruby", VALIDATOR, "--fixture", path, chdir: ROOT)
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
  source_route_ref = candidate.dig(
    "phase_execution_envelope", "authority_basis", "source_route_ref"
  )
  source_route = source_route_ref.is_a?(String) ? candidate[source_route_ref] : nil
  next false unless source_route.is_a?(Hash)

  Array(candidate.dig("phase_execution_envelope", "task_ledger")).any? do |entry|
    next false unless entry.is_a?(Hash) &&
                      entry.dig("contract", "sha256") == terminal_contract_identity["sha256"] &&
                      entry.dig("contract", "byte_length") == terminal_contract_identity["byte_length"]
    source_tasks = Array(source_route["task_plan"])
    next false unless source_tasks.length == 1 && source_tasks.first.is_a?(Hash) &&
                      source_tasks.first["task_id"] == entry["task_id"]
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
  begin
  File.chmod(0o700, fixtures)

  unless FounderDelegationContinuity::DELEGATED_TASK_ID_RE.match?("AIOS-P2-998") &&
         FounderDelegationContinuity::DELEGATED_TASK_ID_RE.match?("AIOS-P2-998_GENERIC_FIXTURE") &&
         !FounderDelegationContinuity::DELEGATED_TASK_ID_RE.match?("AIOS-P2-0998") &&
         !FounderDelegationContinuity::DELEGATED_TASK_ID_RE.match?("AIOS-P2-998_")
    raise "delegated independent Task id compatibility regex drift"
  end
  assertions += 1
  puts "PASS delegated Task id accepts exact bare and suffixed forms"

  runtime_task_id = "AIOS-P2-998_RUNTIME_REPAIR_EXHAUSTION_FIXTURE"
  synthetic_canonical_commit, synthetic_commit_error, synthetic_commit_status =
    Open3.capture3("git", "-C", ROOT, "rev-parse", "HEAD^{commit}")
  synthetic_canonical_tree, synthetic_tree_error, synthetic_tree_status =
    Open3.capture3("git", "-C", ROOT, "rev-parse", "HEAD^{tree}")
  unless synthetic_commit_status.success? && synthetic_tree_status.success?
    raise "synthetic canonical identity failed: #{synthetic_commit_error} #{synthetic_tree_error}"
  end
  synthetic_canonical_commit = synthetic_canonical_commit.strip
  synthetic_canonical_tree = synthetic_canonical_tree.strip
  runtime_evidence_root = File.join(fixtures, "evidence")
  attack_root = File.join(fixtures, "attacks")
  %w[decision reviews runtime].each do |name|
    FileUtils.mkdir_p(File.join(runtime_evidence_root, name))
  end
  File.chmod(0o700, runtime_evidence_root)
  FileUtils.mkdir_p(File.join(attack_root, "reviews"))
  runtime_entry = {
    "task_id" => runtime_task_id,
    "route_id" => "AIOS-P2-998_RUNTIME_REPAIR_EXHAUSTION_FIXTURE_PHASE_DELEGATED_ROUTE",
    "status" => "TERMINAL_PREACTIVATION_RUNTIME_REPAIR_EXHAUSTED_NON_PASS"
  }
  runtime_contract = {
    "budget" => {
      "engineering_hours" => 12,
      "calendar_days" => 3,
      "implementation_iterations" => 2,
      "candidates" => 1
    },
    "max_same_task_repairs" => 1
  }
  runtime_outcome = {
    "status" => runtime_entry["status"],
    "candidate_commit" => nil,
    "candidate_tree" => nil,
    "sealed_formal_value_result" => "NOT_STARTED_PREACTIVATION_RUNTIME_NON_PASS",
    "cto_review" => "NON_PASS",
    "security_review" => "NON_PASS",
    "quality_review" => "NON_PASS",
    "terminal_receipt" => write_json_identity(
      fixtures, "evidence/decision/synthetic-terminal-outcome.json",
      { "schema_version" => "synthetic-terminal-outcome/v1", "task_id" => runtime_task_id }
    ),
    "terminal_receipt_chronology" => {
      "task_id" => runtime_task_id,
      "authoritative_terminal_event_at_utc" => "2026-08-10T12:34:56Z",
      "recorded_at_utc_classification" => "INVALID_FUTURE_METADATA_NOT_CHRONOLOGY",
      "chronology_source" => "CANONICAL_TRUTH_TERMINAL_EVENT"
    },
    "capability_credit" => 0,
    "candidate_integrated" => false,
    "canonical_make_verify" => "NOT_INVOKED_TERMINAL_PREACTIVATION_RUNTIME_NON_PASS"
  }
  synthetic_truth_chronology = deep_copy(runtime_outcome.fetch("terminal_receipt_chronology"))
  shared_multi_role_review = write_json_identity(
    fixtures, "attacks/runtime-shared-cto-security-review.json",
    {
      "schema_version" => "synthetic-shared-terminal-review/v1",
      "task_id" => runtime_task_id,
      "review_role" => "cto_security",
      "target_verdict" => "NON_PASS"
    }
  ).merge("verdict" => "NON_PASS")

  install_record = {
    "schema_version" => "p2-998-worker-runtime-install-receipt/v2",
    "task_id" => runtime_task_id,
    "status" => "PUBLISHED_CREATE_ONCE",
    "install_case" => "REAL",
    "install_mode" => "REAL",
    "formal_execution_authorized" => false,
    "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS,
    "canonical" => {
      "clean" => true, "commit" => synthetic_canonical_commit,
      "tree" => synthetic_canonical_tree
    }
  }
  install_identity = write_json_identity(fixtures, "evidence/runtime/runtime-install.json", install_record)
  observer_identity = write_json_identity(
    fixtures, "evidence/runtime/runtime-observer.json",
    {
      "schema_version" => "p2-998-security-worker-probe-observer/v1",
      "task_id" => runtime_task_id, "status" => "NON_PASS",
      "formal_execution_authorized" => false, "no_retry" => true,
      "probe_count_expected" => 20, "probe_count_executed" => 1,
      "unique_probe_count" => 1, "failed_probe" => "PROBE_FIXTURE",
      "results" => [{ "ordinal" => 1, "mode" => "PROBE_FIXTURE", "pass" => false }]
    }
  )
  postinstall_identity = write_json_identity(
    fixtures, "evidence/runtime/runtime-postinstall-review.json",
    {
      "schema_version" => "p2-998-security-worker-runtime-postinstall-receipt/v1",
      "task_id" => runtime_task_id, "status" => "NON_PASS",
      "review_role" => "INDEPENDENT_SECURITY_EXTERNAL_OBSERVER",
      "formal_execution_authorized" => false,
      "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS,
      "cleanup" => { "child_absent" => true, "output_empty" => true },
      "first_failure" => { "classification" => "P0_SYNTHETIC_LAUNCH_FAILURE" },
      "probe_matrix" => {
        "expected_probe_count" => 20, "executed_probe_count" => 1, "no_retry" => true,
        "observer_receipt" => observer_identity
      }
    }
  )
  synthetic_reviewed_tuple = %w[profile launcher manifest inventory seal installer].to_h do |name|
    [name, { "byte_length" => 2, "sha256" => Digest::SHA256.hexdigest(name) }]
  end
  review_values = {
    "cto" => {
      "schema_version" => "p2-998-cto-terminal-runtime-repair-exhausted-review/v1",
      "task_id" => runtime_task_id,
      "review" => { "review_role" => "INDEPENDENT_CTO_ARCHITECTURE_REVIEWER" },
      "verdict" => "NON_PASS",
      "evidence_bindings" => {
        "v1_install_receipt" => install_identity,
        "security_postinstall_review" => postinstall_identity
      },
      "v1_failure" => { "probe_count_expected" => 20, "probe_count_executed" => 1,
                         "cleanup_residual_count" => 0 },
      "v2_reviewed_tuple" => {
        "files" => synthetic_reviewed_tuple,
        "p0" => { "classification" => "P0_SYNTHETIC_BINDING_MISMATCH",
                   "launcher_embedded_manifest_sha256" => "1" * 64,
                   "actual_manifest_sha256" => synthetic_reviewed_tuple.dig("manifest", "sha256") }
      },
      "formal" => { "execution_authorized" => false, "execution_started" => false,
                      "http_dispatches" => 0, "logical_cells_executed" => 0 },
      "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS
    },
    "security" => {
      "schema_version" => "p2-998-security-terminal-runtime-repair-exhausted-review/v1",
      "task_id" => runtime_task_id, "review_role" => "INDEPENDENT_SECURITY_REVIEWER",
      "verdict" => "TASK_NON_PASS",
      "v1_immutable_runtime" => {
        "real_install_receipt" => install_identity,
        "probe_observer_receipt" => observer_identity,
        "security_postinstall_receipt" => postinstall_identity,
        "p0" => { "classification" => "P0_SYNTHETIC_LAUNCH_FAILURE",
                   "probe_count_planned" => 20, "probe_count_executed" => 1 }
      },
      "v2_reviewed_repair_candidate" => {
        "profile" => synthetic_reviewed_tuple.fetch("profile"),
        "launcher" => synthetic_reviewed_tuple.fetch("launcher").merge(
          "embedded_manifest_sha256" => "1" * 64
        ),
        "actual_manifest" => synthetic_reviewed_tuple.fetch("manifest"),
        "inventory" => synthetic_reviewed_tuple.fetch("inventory"),
        "seal" => synthetic_reviewed_tuple.fetch("seal"),
        "installer" => synthetic_reviewed_tuple.fetch("installer"),
        "installed" => false, "target_absent_at_review" => true,
        "p0" => { "actual_manifest_sha256" => synthetic_reviewed_tuple.dig("manifest", "sha256"),
                   "launcher_expected_manifest_sha256" => "1" * 64 }
      },
      "formal_execution" => { "authorized" => false, "formal_dispatch_count" => 0,
                                "capability_credit" => false },
      "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS
    },
    "quality" => {
      "schema_version" => "p2-998-quality-terminal-runtime-repair-exhausted-review/v1",
      "task_id" => runtime_task_id,
      "artifact_type" => "INDEPENDENT_QUALITY_TERMINAL_RUNTIME_REPAIR_EXHAUSTED_REVIEW",
      "verdict" => {
        "p0_review_integrity_blockers" => 0, "p1_review_integrity_blockers" => 0,
        "quality_review_status" => "PASS_TERMINAL_FACT_CLOSURE",
        "task_target_verdict" => "NON_PASS", "terminal_reason" => "FIXTURE_EXHAUSTED"
      },
      "facts" => {
        "formal_http_dispatches_completed" => 0,
        "formal_logical_cells_completed" => 0, "capability_credit" => 0,
        "p2_credit" => 0, "canonical_source_mutation" => false,
        "runtime_v1" => {
          "install_receipt" => install_identity, "installed" => true,
          "residual_output_count" => 0,
          "first_probe_attempt" => { "attempted" => 1, "declared_matrix_size" => 20 }
        },
        "runtime_v2" => {
          "installed" => false, "executed" => false,
          "post_review_corrected_bytes_reviewed" => false,
          "tuple" => synthetic_reviewed_tuple,
          "cto_review" => { "embedded_manifest_sha256" => "1" * 64,
                             "exact_manifest_sha256" => synthetic_reviewed_tuple.dig("manifest", "sha256"),
                             "verdict" => "NON_PASS" }
        }
      },
      "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS
    }
  }
  review_identities = review_values.to_h do |role, value|
    identity = write_json_identity(fixtures, "evidence/reviews/runtime-#{role}-review.json", value)
    [role, identity.merge("verdict" => "NON_PASS")]
  end
  reviewed_runtime_identities = {}
  (2..2).each do |iteration|
    reviewed_runtime_identities[iteration] = write_json_identity(
      fixtures, "evidence/runtime/reviewed-runtime-#{iteration}.json",
      {
        "schema_version" => "phase-delegated-reviewed-runtime-repair-identity/v1",
        "task_id" => runtime_task_id, "status" => "NON_PASS_PREINSTALL",
        "iteration" => iteration, "same_task_repair_ordinal" => iteration - 1,
        "installed" => false, "executed" => false,
        "target" => { "path" => "/private/tmp/synthetic-runtime-target-#{iteration}",
                      "absent_at_exact_review" => true },
        "failure" => {
          "classification" => "P0_SYNTHETIC_BINDING_MISMATCH",
          "launcher_embedded_manifest_sha256" => "1" * 64,
          "actual_manifest_sha256" => synthetic_reviewed_tuple.dig("manifest", "sha256")
        },
        "reviewed_tuple" => synthetic_reviewed_tuple,
        "independent_reviews" => review_identities.transform_values do |identity|
          identity.slice("path", "byte_length", "sha256")
        end,
        "post_review_corrected_bytes" => {
          "authorization" => "UNAUTHORIZED_DO_NOT_INSTALL",
          "identity" => "UNBOUND_NOT_READ", "reviewed_or_adopted" => false
        }
      }
    )
  end
  attempt = lambda do |iteration|
    first = iteration == 1
    {
      "iteration" => iteration,
      "same_task_repair_ordinal" => iteration - 1,
      "status" => first ? "NON_PASS_PRE_SANDBOX" : "NON_PASS_PREINSTALL",
      "installed" => first,
      "executed" => first,
      "failure_classification" => first ? "P0_SYNTHETIC_LAUNCH_FAILURE" : "P0_SYNTHETIC_BINDING_MISMATCH",
      "formal_dispatches" => 0,
      "evidence" => if first
                        [
                          { "kind" => "RUNTIME_INSTALL_RECEIPT", "identity" => install_identity },
                          { "kind" => "INDEPENDENT_OBSERVER", "identity" => observer_identity },
                          { "kind" => "INDEPENDENT_SECURITY_REVIEW",
                            "identity" => postinstall_identity }
                        ]
                      else
                        [
                          { "kind" => "REVIEWED_RUNTIME_IDENTITY",
                            "identity" => reviewed_runtime_identities.fetch(iteration) },
                          { "kind" => "INDEPENDENT_CTO_REVIEW",
                            "identity" => review_identities.fetch("cto").slice(
                              "path", "byte_length", "sha256"
                            ) },
                          { "kind" => "INDEPENDENT_SECURITY_REVIEW",
                            "identity" => review_identities.fetch("security").slice(
                              "path", "byte_length", "sha256"
                            ) },
                          { "kind" => "INDEPENDENT_QUALITY_REVIEW",
                            "identity" => review_identities.fetch("quality").slice(
                              "path", "byte_length", "sha256"
                            ) }
                        ]
                      end,
      "observations" => if first
                          [
                            { "name" => "probe_count_planned", "value" => 20 },
                            { "name" => "probe_count_executed", "value" => 1 },
                            { "name" => "sandbox_entered", "value" => false },
                            { "name" => "cleanup_residual_count", "value" => 0 }
                          ]
                        else
                          [
                            { "name" => "target_absent_at_review", "value" => true },
                            { "name" => "launcher_manifest_binding_exact", "value" => false }
                          ]
                        end
    }
  end
  runtime_receipt = {
    "schema_version" =>
      "phase-delegated-preactivation-runtime-repair-exhausted-terminal-receipt/v1",
    "task_id" => runtime_task_id,
    "route_id" => runtime_entry["route_id"],
    "status" => runtime_entry["status"],
    "recorded_at_utc" => "2026-08-12T00:00:00Z",
    "activation_parent" => {
      "commit" => synthetic_canonical_commit, "tree" => synthetic_canonical_tree
    },
    "canonical_before_terminal_sync" => {
      "commit" => synthetic_canonical_commit, "tree" => synthetic_canonical_tree
    },
    "runtime_attempts" => (1..2).map { |iteration| attempt.call(iteration) },
    "repair_accounting" => {
      "implementation_iterations_limit" => 2,
      "implementation_iterations_consumed" => 2,
      "implementation_iterations_remaining" => 0,
      "same_task_repairs_limit" => 1,
      "same_task_repairs_consumed" => 1,
      "same_task_repairs_remaining" => 0,
      "exhausted" => true
    },
    "candidate" => { "created" => false, "commit" => nil, "tree" => nil,
                     "source_manifest_created" => false, "integrated" => false },
    "formal_execution" => {
      "authorized" => false, "http_dispatches" => 0, "logical_cells" => 0,
      "held_dispatches" => 0, "metrics_computed" => 0,
      "benchmark_result" => "NOT_AVAILABLE"
    },
    "final_reviews" => review_identities,
    "lifecycle_boundary" => {
      "task_terminal" => true, "phase_status" => "ACTIVE_INCOMPLETE",
      "project_status" => "ACTIVE", "long_term_goal_status" => "ACTIVE",
      "project_actual_completion" => false, "p3_status" => "HOLD"
    },
    "product_source_mutation" => false,
    "capability_credit" => 0,
    "p2_credit" => 0,
    "canonical_make_verify" => "NOT_INVOKED_TERMINAL_PREACTIVATION_RUNTIME_NON_PASS",
    "next_action" => "FOUNDER_RESERVED_DECISION_PHASE_ENVELOPE_EXHAUSTED",
    "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS,
    "post_review_corrected_bytes_adopted" => false
  }

  trigger_identity = write_json_identity(
    fixtures, "evidence/decision/SYNTHETIC_FOUNDER_RESERVED_TRIGGER_EVIDENCE_V1.json",
    { "schema_version" => "synthetic-founder-trigger/v1", "task_id" => runtime_task_id }
  )
  inventory_identity = write_json_identity(
    fixtures, "evidence/INVENTORY.sha256",
    { "schema_version" => "synthetic-terminal-inventory/v1", "task_id" => runtime_task_id }
  )
  seal_identity = write_json_identity(
    fixtures, "evidence/SEAL.json",
    { "schema_version" => "synthetic-terminal-seal/v1", "task_id" => runtime_task_id }
  )
  payload_identities = [
    inventory_identity, seal_identity, runtime_outcome.fetch("terminal_receipt"), trigger_identity,
    *review_identities.values.map { |identity| identity.slice("path", "byte_length", "sha256") },
    *runtime_receipt.fetch("runtime_attempts").flat_map do |runtime_attempt|
      runtime_attempt.fetch("evidence").map { |binding| binding.fetch("identity") }
    end
  ].uniq
  payload_identities.each { |identity| File.chmod(0o400, identity.fetch("path")) }
  %w[decision reviews runtime].each do |name|
    File.chmod(0o500, File.join(runtime_evidence_root, name))
  end
  installed_files = payload_identities.to_h do |identity|
    relative = Pathname.new(identity.fetch("path")).relative_path_from(
      Pathname.new(File.realpath(runtime_evidence_root))
    ).to_s
    stat = File.lstat(identity.fetch("path"))
    [relative, {
      "byte_length" => identity.fetch("byte_length"), "bytes_equal" => true,
      "sha256" => identity.fetch("sha256"),
      "source" => { "dev" => stat.dev, "ino" => stat.ino, "mode" => "0400",
                    "nlink" => 1, "path" => identity.fetch("path"), "uid" => stat.uid },
      "target" => { "dev" => stat.dev, "ino" => stat.ino, "mode" => "0400",
                    "nlink" => 1, "path" => identity.fetch("path"), "uid" => stat.uid }
    }]
  end
  directory_inodes = %w[. decision reviews runtime].map do |relative|
    path = relative == "." ? runtime_evidence_root : File.join(runtime_evidence_root, relative)
    stat = File.lstat(path)
    { "dev" => stat.dev, "ino" => stat.ino,
      "mode" => relative == "." ? "0700" : "0500", "path" => relative, "uid" => stat.uid }
  end
  evidence_stat = File.lstat(runtime_evidence_root)
  canonical_stat = File.lstat(ROOT)
  task_root_stat = File.lstat(fixtures)
  source_payload = installed_files.reject do |relative, _record|
    %w[INVENTORY.sha256 SEAL.json].include?(relative)
  end.transform_values { |record| record.fetch("sha256") }
  terminal_install_receipt = {
    "schema_version" => "p2-998-terminal-evidence-create-once-install-receipt/v1",
    "task_id" => runtime_task_id, "execution_mode" => "REAL",
    "authoritative_install" => true, "status" => "PUBLISHED_CREATE_ONCE",
    "publication" => "ATOMIC_EXCLUSIVE_WHOLE_EVIDENCE_ROOT_RENAME",
    "publication_flags" => {
      "rename_excl" => 4, "rename_nofollow_any" => 16,
      "renameatx_np" => true, "same_volume_required" => true
    },
    "postpublish_verification" =>
      "FULL_CLOSED_TREE_INODE_NLINK_MODE_SHA_AND_CANONICAL_REBIND_REQUIRED_BEFORE_SUCCESS",
    "canonical" => {
      "commit" => synthetic_canonical_commit, "tree" => synthetic_canonical_tree,
      "repository" => ROOT,
      "dev" => canonical_stat.dev, "ino" => canonical_stat.ino, "uid" => canonical_stat.uid
    },
    "task_root" => {
      "path" => fixtures, "dev" => task_root_stat.dev, "ino" => task_root_stat.ino,
      "uid" => task_root_stat.uid, "mode" => "0700"
    },
    "source_root" => {
      "dev" => evidence_stat.dev, "ino" => evidence_stat.ino, "uid" => evidence_stat.uid,
      "mode" => "0500", "directory_count" => 3,
      "file_count" => installed_files.length,
      "inventory" => installed_files.fetch("INVENTORY.sha256").slice("byte_length", "sha256"),
      "seal" => installed_files.fetch("SEAL.json").slice("byte_length", "sha256"),
      "payload" => source_payload
    },
    "formal_http_dispatches_completed" => 0, "formal_logical_cells_completed" => 0,
    "product_source_mutation" => false,
    "external_effects" => FounderDelegationContinuity::FALSE_EXTERNAL_EFFECTS,
    "evidence_root" => { "dev" => evidence_stat.dev, "ino" => evidence_stat.ino,
                         "mode" => "0700", "path" => File.realpath(runtime_evidence_root),
                         "uid" => evidence_stat.uid },
    "directory_modes" => { "evidence_root" => "0700", "sealed_descendants" => "0500" },
    "file_mode" => "0400",
    "expected_tree" => {
      "directories" => %w[. decision reviews runtime], "directory_inodes" => directory_inodes,
      "files" => (installed_files.keys + ["P2_998_TERMINAL_EVIDENCE_INSTALL_RECEIPT_V1.json"]).sort
    },
    "installed_files" => installed_files,
    "payload_file_count" => installed_files.length,
    "published_file_count" => installed_files.length + 1,
    "runtime" => {
      "environment" => {
        "LANG" => "C", "LC_ALL" => "C", "PATH" => "/usr/bin:/bin",
        "TMPDIR" => "/private/tmp", "__CF_USER_TEXT_ENCODING" => "0x1F5:0x19:0x34",
        "execution_mode" => "REAL"
      },
      "git_executable" => {
        "byte_length" => 1, "dev" => 1, "ino" => 1, "mode" => "0755", "nlink" => 1,
        "path" => "/usr/bin/git", "sha256" => "1" * 64, "uid" => 0
      },
      "installer" => {
        "byte_length" => 1, "dev" => 1, "ino" => 1, "mode" => "0500", "nlink" => 1,
        "path" => "/private/tmp/install_p2_998_terminal_evidence_v1.rb",
        "sha256" => "2" * 64, "uid" => 501
      },
      "ruby_launcher" => {
        "byte_length" => 1, "dev" => 1, "ino" => 1, "mode" => "0555", "nlink" => 1,
        "path" => "/usr/bin/ruby", "sha256" => "3" * 64, "uid" => 0
      },
      "ruby_runtime" => {
        "byte_length" => 1, "dev" => 1, "ino" => 1, "mode" => "0755", "nlink" => 1,
        "path" => "/System/Library/Frameworks/Ruby.framework/Versions/2.6/usr/bin/ruby",
        "sha256" => "4" * 64, "uid" => 0
      },
      "ruby_platform" => "synthetic-darwin", "ruby_version" => "2.6.10"
    }
  }
  runtime_outcome["terminal_evidence_install_receipt"] = write_json_identity(
    fixtures, "evidence/P2_998_TERMINAL_EVIDENCE_INSTALL_RECEIPT_V1.json",
    terminal_install_receipt
  )
  runtime_outcome["terminal_evidence_install_runtime_binding"] =
    deep_copy(terminal_install_receipt.fetch("runtime"))
  runtime_outcome["terminal_evidence_install_runtime_review"] = write_json_identity(
    fixtures,
    "independent-security-terminal-evidence-install-runtime-review.json",
    {
      "schema_version" =>
        "p2-998-security-terminal-evidence-install-runtime-identity-review/v1",
      "task_id" => runtime_task_id,
      "review_role" => "INDEPENDENT_SECURITY_REVIEWER",
      "verdict" => "PASS_EXACT_RUNTIME_IDENTITY_BINDING_ONLY",
      "terminal_install_receipt" =>
        deep_copy(runtime_outcome.fetch("terminal_evidence_install_receipt")),
      "runtime" => deep_copy(terminal_install_receipt.fetch("runtime"))
    }
  )
  File.chmod(0o400, runtime_outcome.dig("terminal_evidence_install_receipt", "path"))
  File.chmod(0o400, runtime_outcome.dig("terminal_evidence_install_runtime_review", "path"))
  runtime_contract["terminal_outcome"] = deep_copy(runtime_outcome)

  expect_method_pass("generic-runtime-repair-exhausted-alternate-task-budget-pass") do
    FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
      runtime_entry, runtime_contract, runtime_receipt, runtime_outcome,
      truth_chronology: synthetic_truth_chronology,
      truth_terminal_event_at: synthetic_truth_chronology["authoritative_terminal_event_at_utc"]
    )
  end
  assertions += 1

  expect_method_non_pass("generic-runtime-truth-terminal-event-time-drift", "chronology drift") do
    FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
      runtime_entry, runtime_contract, runtime_receipt, runtime_outcome,
      truth_chronology: synthetic_truth_chronology,
      truth_terminal_event_at: "2000-01-01T00:00:00Z"
    )
  end
  assertions += 1

  off_root_install_identity = write_json_identity(
    fixtures, "attacks/P2_998_TERMINAL_EVIDENCE_INSTALL_RECEIPT_V1.json",
    terminal_install_receipt
  )
  off_root_outcome = deep_copy(runtime_outcome)
  off_root_outcome["terminal_evidence_install_receipt"] = off_root_install_identity
  expect_method_non_pass("generic-runtime-terminal-install-off-root-reject", "outside its durable root") do
    FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
      runtime_entry, runtime_contract, runtime_receipt, off_root_outcome,
      truth_chronology: synthetic_truth_chronology,
      truth_terminal_event_at: synthetic_truth_chronology["authoritative_terminal_event_at_utc"]
    )
  end
  assertions += 1

  exact_install_path = runtime_outcome.dig("terminal_evidence_install_receipt", "path")
  exact_install_bytes = File.binread(exact_install_path)
  trigger_drift = deep_copy(terminal_install_receipt)
  trigger_key = trigger_drift.fetch("installed_files").keys.find do |name|
    name.include?("FOUNDER_RESERVED_TRIGGER")
  end
  trigger_drift.fetch("installed_files").fetch(trigger_key)["sha256"] = "d" * 64
  begin
    File.chmod(0o600, exact_install_path)
    File.binwrite(exact_install_path, JSON.generate(trigger_drift))
    File.chmod(0o400, exact_install_path)
    trigger_drift_outcome = deep_copy(runtime_outcome)
    trigger_drift_outcome["terminal_evidence_install_receipt"] = identity_for(exact_install_path)
    expect_method_non_pass("generic-runtime-terminal-trigger-installed-sha-reject",
                           "preactivation terminal") do
      FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
        runtime_entry, runtime_contract, runtime_receipt, trigger_drift_outcome,
        truth_chronology: synthetic_truth_chronology,
        truth_terminal_event_at: synthetic_truth_chronology["authoritative_terminal_event_at_utc"]
      )
    end
    assertions += 1
  ensure
    File.chmod(0o600, exact_install_path)
    File.binwrite(exact_install_path, exact_install_bytes)
    File.chmod(0o400, exact_install_path)
  end

  install_semantic_mutations = {
    "publication-flags-drift" => lambda do |value|
      value.fetch("publication_flags").merge!(
        "rename_excl" => 0, "rename_nofollow_any" => 0,
        "renameatx_np" => false, "same_volume_required" => false
      )
    end,
    "postpublish-verification-drift" => lambda do |value|
      value["postpublish_verification"] = "NONE"
    end,
    "canonical-commit-drift" => lambda do |value|
      value.fetch("canonical")["commit"] = "f" * 40
    end,
    "task-root-inode-drift" => lambda do |value|
      value.fetch("task_root")["ino"] += 1
    end,
    "source-root-payload-drift" => lambda do |value|
      key = value.dig("source_root", "payload").keys.first
      value.dig("source_root", "payload")[key] = "e" * 64
    end,
    "installed-source-inode-drift" => lambda do |value|
      value.fetch("installed_files").values.first.fetch("source")["ino"] += 1
    end,
    "runtime-installer-path-drift" => lambda do |value|
      value.dig("runtime", "installer")["path"] = "/private/tmp/nonexistent-installer.rb"
    end,
    "runtime-version-drift" => lambda do |value|
      value.fetch("runtime")["ruby_version"] = "FORGED"
    end,
    "runtime-missing" => lambda { |value| value.delete("runtime") },
    "unexpected-top-level-field" => lambda { |value| value["unexpected"] = true }
  }
  install_semantic_mutations.each do |name, mutate|
    mutated_install = deep_copy(terminal_install_receipt)
    mutate.call(mutated_install)
    begin
      File.chmod(0o600, exact_install_path)
      File.binwrite(exact_install_path, JSON.generate(mutated_install))
      File.chmod(0o400, exact_install_path)
      mutated_outcome = deep_copy(runtime_outcome)
      mutated_outcome["terminal_evidence_install_receipt"] = identity_for(exact_install_path)
      expect_method_non_pass("generic-runtime-terminal-install-#{name}", "preactivation") do
        FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
          runtime_entry, runtime_contract, runtime_receipt, mutated_outcome,
          truth_chronology: synthetic_truth_chronology,
          truth_terminal_event_at: synthetic_truth_chronology["authoritative_terminal_event_at_utc"]
        )
      end
      assertions += 1
    ensure
      File.chmod(0o600, exact_install_path)
      File.binwrite(exact_install_path, exact_install_bytes)
      File.chmod(0o400, exact_install_path)
    end
  end

  unexpected_leaf = File.join(runtime_evidence_root, "UNLISTED_LEAF.json")
  begin
    File.binwrite(unexpected_leaf, "{}\n")
    File.chmod(0o400, unexpected_leaf)
    expect_method_non_pass("generic-runtime-terminal-unlisted-leaf-reject",
                           "actual closed tree drift") do
      FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
        runtime_entry, runtime_contract, runtime_receipt, runtime_outcome,
        truth_chronology: synthetic_truth_chronology,
        truth_terminal_event_at: synthetic_truth_chronology["authoritative_terminal_event_at_utc"]
      )
    end
    assertions += 1
  ensure
    File.chmod(0o600, unexpected_leaf) if File.exist?(unexpected_leaf)
    File.unlink(unexpected_leaf) if File.exist?(unexpected_leaf)
  end

  role_spoof_review = deep_copy(review_values.fetch("cto"))
  role_spoof_review.fetch("review")["review_role"] = "INDEPENDENT_SECURITY_REVIEWER"
  role_spoof_identity = write_json_identity(
    fixtures, "attacks/reviews/runtime-cto-role-spoof-review.json", role_spoof_review
  ).merge("verdict" => "NON_PASS")

  runtime_mutations = {
    "candidate-injection" => lambda { |receipt, _contract, _outcome| receipt.fetch("candidate")["created"] = true },
    "iteration-accounting-drift" => lambda { |receipt, _contract, _outcome| receipt.fetch("repair_accounting")["implementation_iterations_consumed"] = 1 },
    "repair-accounting-drift" => lambda { |receipt, _contract, _outcome| receipt.fetch("repair_accounting")["same_task_repairs_consumed"] = 0 },
    "formal-dispatch-drift" => lambda { |receipt, _contract, _outcome| receipt.fetch("formal_execution")["http_dispatches"] = 1 },
    "external-effect-drift" => lambda { |receipt, _contract, _outcome| receipt.fetch("external_effects")["network"] = true },
    "capability-credit-drift" => lambda { |receipt, _contract, _outcome| receipt["capability_credit"] = 1 },
    "review-verdict-drift" => lambda { |receipt, _contract, _outcome| receipt.dig("final_reviews", "quality")["verdict"] = "PASS" },
    "review-identity-hash-drift" => lambda { |receipt, _contract, _outcome| receipt.dig("final_reviews", "security")["sha256"] = "f" * 64 },
    "duplicate-review-identity" => lambda { |receipt, _contract, _outcome| receipt.fetch("final_reviews")["cto"] = deep_copy(shared_multi_role_review); receipt.fetch("final_reviews")["security"] = deep_copy(shared_multi_role_review) },
    "role-spoof-review" => lambda { |receipt, _contract, _outcome| receipt.fetch("final_reviews")["cto"] = deep_copy(role_spoof_identity) },
    "fake-independent-evidence-kind" => lambda { |receipt, _contract, _outcome| receipt.fetch("runtime_attempts").first.fetch("evidence")[1]["kind"] = "INDEPENDENT_FAKE" },
    "missing-initial-evidence" => lambda { |receipt, _contract, _outcome| receipt.fetch("runtime_attempts").first.fetch("evidence").pop },
    "extra-initial-evidence" => lambda { |receipt, _contract, _outcome| receipt.fetch("runtime_attempts").first.fetch("evidence") << { "kind" => "INDEPENDENT_EXTRA", "identity" => deep_copy(observer_identity) } },
    "initial-observations-cleared" => lambda { |receipt, _contract, _outcome| receipt.fetch("runtime_attempts").first["observations"] = [] },
    "initial-executed-self-report-drift" => lambda { |receipt, _contract, _outcome| receipt.fetch("runtime_attempts").first["executed"] = false },
    "repair-failure-crossbind-drift" => lambda { |receipt, _contract, _outcome| receipt.fetch("runtime_attempts")[1]["failure_classification"] = "P0_OTHER_BINDING_FAILURE" },
    "repair-review-crossbind-drift" => lambda { |receipt, _contract, _outcome| repair = receipt.fetch("runtime_attempts")[1].fetch("evidence"); repair.find { |binding| binding["kind"] == "INDEPENDENT_SECURITY_REVIEW" }["identity"] = deep_copy(review_identities.fetch("cto").slice("path", "byte_length", "sha256")) },
    "initial-review-reverse-binding-drift" => lambda { |receipt, _contract, _outcome| observer = JSON.parse(File.binread(observer_identity.fetch("path"))); observer["probe_count_expected"] = 21; observer_attack = write_json_identity(fixtures, "attacks/runtime-observer-review-drift.json", observer); postinstall = JSON.parse(File.binread(postinstall_identity.fetch("path"))); postinstall.dig("probe_matrix")["expected_probe_count"] = 21; postinstall.dig("probe_matrix")["observer_receipt"] = observer_attack; postinstall_attack = write_json_identity(fixtures, "attacks/runtime-postinstall-review-drift.json", postinstall); initial = receipt.fetch("runtime_attempts").first; initial.fetch("observations").find { |value| value["name"] == "probe_count_planned" }["value"] = 21; initial.fetch("evidence").find { |value| value["kind"] == "INDEPENDENT_OBSERVER" }["identity"] = observer_attack; initial.fetch("evidence").find { |value| value["kind"] == "INDEPENDENT_SECURITY_REVIEW" }["identity"] = postinstall_attack },
    "repair-tuple-review-reverse-binding-drift" => lambda { |receipt, _contract, _outcome| reviewed = JSON.parse(File.binread(reviewed_runtime_identities.fetch(2).fetch("path"))); reviewed.dig("reviewed_tuple", "manifest")["sha256"] = "3" * 64; reviewed.dig("failure")["actual_manifest_sha256"] = "3" * 64; reviewed_attack = write_json_identity(fixtures, "attacks/reviewed-runtime-tuple-drift.json", reviewed); receipt.fetch("runtime_attempts")[1].fetch("evidence").find { |value| value["kind"] == "REVIEWED_RUNTIME_IDENTITY" }["identity"] = reviewed_attack },
    "terminal-install-identity-drift" => lambda { |_receipt, _contract, outcome| outcome.fetch("terminal_evidence_install_receipt")["sha256"] = "e" * 64 },
    "terminal-runtime-binding-drift" => lambda { |_receipt, _contract, outcome| outcome.dig("terminal_evidence_install_runtime_binding", "installer")["sha256"] = "a" * 64 },
    "terminal-runtime-review-identity-drift" => lambda { |_receipt, _contract, outcome| outcome.fetch("terminal_evidence_install_runtime_review")["sha256"] = "b" * 64 },
    "terminal-chronology-classification-drift" => lambda { |_receipt, _contract, outcome| outcome.dig("terminal_receipt_chronology", "recorded_at_utc_classification").replace("AUTHORITATIVE") },
    "corrected-bytes-adopted" => lambda { |receipt, _contract, _outcome| receipt["post_review_corrected_bytes_adopted"] = true },
    "goal-lifecycle-drift" => lambda { |receipt, _contract, _outcome| receipt.dig("lifecycle_boundary", "long_term_goal_status").replace("COMPLETE") },
    "phase-lifecycle-drift" => lambda { |receipt, _contract, _outcome| receipt.dig("lifecycle_boundary", "phase_status").replace("TERMINAL") },
    "canonical-verification-credit-drift" => lambda { |receipt, _contract, outcome| receipt["canonical_make_verify"] = outcome["canonical_make_verify"] = "PASS" },
    "next-action-drift" => lambda { |receipt, _contract, _outcome| receipt["next_action"] = "MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK" }
  }
  runtime_mutations.each do |name, mutate|
    receipt = deep_copy(runtime_receipt)
    contract = deep_copy(runtime_contract)
    outcome = deep_copy(runtime_outcome)
    mutate.call(receipt, contract, outcome)
    expect_method_non_pass("generic-runtime-#{name}", "preactivation") do
      FounderDelegationContinuity.validate_preactivation_runtime_repair_exhausted_payload!(
        runtime_entry, contract, receipt, outcome,
        truth_chronology: synthetic_truth_chronology,
        truth_terminal_event_at: synthetic_truth_chronology["authoritative_terminal_event_at_utc"]
      )
    end
    assertions += 1
  end

  v1_3_token = "AUTHORIZE_P2_ONE_INDEPENDENT_JAVA_CONTEXT_BENCHMARK_V1"
  v1_3_route = "P2_ONE_INDEPENDENT_JAVA_CONTEXT_BENCHMARK_ROUTE_V1"
  v1_3_packet = <<~PACKET
    - Exact authorization token:
      `#{v1_3_token}`
    - Exact Founder message:
      `#{v1_3_token}；同意一个受限 P2 Task。`
  PACKET
  expect_method_pass("v1-3-exact-token-route-source-packet-pass") do
    FounderDelegationContinuity.validate_v1_3_authorization_binding!(
      v1_3_token, v1_3_route, v1_3_packet
    )
  end
  assertions += 1

  expect_method_non_pass("v1-3-route-drift-reject",
                         "single-Task expansion v1.3 token-to-Route binding drift") do
    FounderDelegationContinuity.validate_v1_3_authorization_binding!(
      v1_3_token, "P2_ONE_INDEPENDENT_JAVA_CONTEXT_BENCHMARK_ROUTE_V2", v1_3_packet
    )
  end
  assertions += 1

  alternate_packet = v1_3_packet.sub(
    "#{v1_3_token}；", "AUTHORIZE_P2_OTHER_CONTEXT_BENCHMARK_V1；"
  )
  expect_method_non_pass("v1-3-source-packet-token-drift-reject",
                         "single-Task expansion v1.3 source packet authorization binding drift") do
    FounderDelegationContinuity.validate_v1_3_authorization_binding!(
      v1_3_token, v1_3_route, alternate_packet
    )
  end
  assertions += 1

  current_disposition = current_truth.fetch("founder_escalation_control").fetch("disposition")
  expect_pass(fixtures, "current-canonical-delegation-disposition", current_truth,
              current_disposition)
  assertions += 1

  if current_disposition == "FOUNDER_DECISION_REQUIRED"
    current_control = current_truth.fetch("founder_escalation_control")
    trigger = deep_copy(current_control.fetch("reserved_trigger"))
    evidence_identity = trigger.fetch("evidence")
    evidence = JSON.parse(File.binread(evidence_identity.fetch("path")))
    evidence["source_route_id"] = "P2_UNBOUND_THIRD_ROUTE_V1"
    trigger["evidence"] = write_json_identity(
      fixtures, "unbound-third-trigger-route.json", evidence
    )
    current_route = current_truth.fetch("current_phase_route")
    historical_route = current_truth.fetch(
      current_route.fetch("historical_terminal_route_ref")
    )
    expect_method_non_pass("reserved-trigger-unbound-third-route-reject",
                           "Founder reserved trigger Evidence source Route drift") do
      FounderDelegationContinuity.validate_reserved_trigger_evidence!(
        trigger,
        current_control.fetch("source_event"),
        current_truth.dig("project", "current_phase"),
        historical_route,
        current_truth.fetch("phase_execution_envelope")
      )
    end
    assertions += 1
  end

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
  reserved_control = truth.fetch("founder_escalation_control")
  reserved_route = truth.fetch(
    truth.fetch("current_phase_route").fetch("historical_terminal_route_ref")
  )
  expect_method_non_pass("exhausted-phase-cannot-invent-next-founder-budget",
                         "exhausted Phase decision Evidence must not invent a new Founder budget") do
    FounderDelegationContinuity.validate_reserved_trigger_evidence!(
      reserved_control.fetch("reserved_trigger"),
      reserved_control.fetch("source_event"),
      truth.dig("project", "current_phase"),
      reserved_route,
      truth.fetch("phase_execution_envelope")
    )
  end
  assertions += 1

  truth = deep_copy(reserved_base)
  trigger = JSON.parse(File.binread(
    truth.dig("founder_escalation_control", "reserved_trigger", "evidence", "path")
  ))
  trigger["supporting_evidence"].pop
  truth["founder_escalation_control"]["reserved_trigger"]["evidence"] =
    write_json_identity(fixtures, "missing-terminal-ledger-support.json", trigger)
  reserved_control = truth.fetch("founder_escalation_control")
  reserved_route = truth.fetch(
    truth.fetch("current_phase_route").fetch("historical_terminal_route_ref")
  )
  expect_method_non_pass("exhausted-phase-must-bind-all-terminal-receipts",
                         "Founder budget expansion trigger must bind every consumed Task outcome receipt") do
    FounderDelegationContinuity.validate_reserved_trigger_evidence!(
      reserved_control.fetch("reserved_trigger"),
      reserved_control.fetch("source_event"),
      truth.dig("project", "current_phase"),
      reserved_route,
      truth.fetch("phase_execution_envelope")
    )
  end
  assertions += 1

  truth = deep_copy(terminal_fixture_truth)
  substituted_terminal_entry = truth.fetch("phase_execution_envelope").fetch("task_ledger").find do |entry|
    entry["task_id"] == terminal_entry["task_id"]
  end
  raise "predeclared terminal fixture ledger entry is missing" unless substituted_terminal_entry
  substituted_terminal_entry["outcome_receipt"] = write_json_identity(
    fixtures,
    "superficial-predeclared-terminal-receipt.json",
    {
      "task_id" => substituted_terminal_entry["task_id"],
      "route_id" => substituted_terminal_entry["route_id"],
      "status" => substituted_terminal_entry["status"]
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

  truth = deep_copy(current_truth)
  truth["claim_boundary"]["p2_phase_envelope_status"] =
    truth.dig("phase_execution_envelope", "status") == "EXHAUSTED" ?
      "TASK_CAPACITY_RESERVED" : "EXHAUSTED"
  expect_non_pass(fixtures, "claim-boundary-envelope-status-drift", truth,
                  "delegated independent Task claim-boundary Phase envelope status drift")
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
  ensure
    if defined?(runtime_evidence_root) && runtime_evidence_root && File.directory?(runtime_evidence_root)
      Dir.glob(File.join(runtime_evidence_root, "**", "*"), File::FNM_DOTMATCH).each do |path|
        next if [".", ".."].include?(File.basename(path))
        stat = File.lstat(path)
        File.chmod(stat.directory? ? 0o700 : 0o600, path) unless stat.symlink?
      end
      File.chmod(0o700, runtime_evidence_root)
    end
  end
end

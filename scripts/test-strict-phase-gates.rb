#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"

ROOT = File.expand_path("..", __dir__)
TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
VALIDATOR = File.join(ROOT, "scripts/validate-aios-governance.sh")
AUDIT_ROOT = "/Users/lijunpeng/Developer/.sourcelens-audit"
REVIEW_ROOT = File.join(AUDIT_ROOT, "independent-reviews")
ATTACHMENT_ROOT = "/Users/lijunpeng/.codex/attachments"

def identity(path)
  bytes = File.binread(path)
  {
    "path" => path,
    "byte_length" => bytes.bytesize,
    "sha256" => Digest::SHA256.hexdigest(bytes)
  }
end

def write_json(path, object)
  File.binwrite(path, JSON.pretty_generate(object) + "\n")
  identity(path)
end

def run_phase_fixture(path, phase, task, action)
  Open3.capture3(
    VALIDATOR,
    "--test-phase-predecessor-fixture",
    path,
    phase,
    task,
    action,
    chdir: ROOT
  )
end

FileUtils.mkdir_p(REVIEW_ROOT)
audit = Dir.mktmpdir("strict-phase-gates-", AUDIT_ROOT)
reviews = Dir.mktmpdir("strict-phase-gate-reviews-", REVIEW_ROOT)
attachment = Dir.mktmpdir("strict-phase-gate-founder-", ATTACHMENT_ROOT)
begin
  truth = YAML.safe_load(
    File.binread(TRUTH),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  commit, commit_stderr, commit_status = Open3.capture3("git", "-C", ROOT, "rev-parse", "HEAD")
  raise commit_stderr unless commit_status.success?
  commit = commit.strip
  tree, tree_stderr, tree_status = Open3.capture3("git", "-C", ROOT, "show", "-s", "--format=%T", commit)
  raise tree_stderr unless tree_status.success?
  tree = tree.strip

  p1 = truth.fetch("strict_phase_gate_ledger").fetch("phases").fetch("P1")
  missing_ids = p1.fetch("required_items").select { |_id, item| item["status"] == "MISSING" }.keys
  raise "unexpected P1 missing Gate set" unless
    missing_ids == %w[REPRODUCIBLE_BASELINE_REPORT P2_CONTEXT_ENGINE_PREREGISTRATION]

  missing_ids.each_with_index do |item_id, index|
    task_number = 990 + index
    task_id = format("AIOS-P1-%03d_STRICT_GATE_POSITIVE_FIXTURE", task_number)
    history_key = format("aios_p1_%03d", task_number)
    manifest_path = File.join(audit, "#{item_id}-manifest.json")
    manifest = write_json(
      manifest_path,
      {
        "schema_version" => "strict-gate-evidence-manifest/v1",
        "phase" => "P1",
        "required_item_id" => item_id,
        "task_id" => task_id,
        "candidate_commit" => commit,
        "candidate_tree" => tree
      }
    )
    review_identities = {}
    {
      "cto" => ["CTO", "11111111-1111-4111-8111-%012d" % task_number],
      "security" => ["SECURITY", "22222222-2222-4222-8222-%012d" % task_number],
      "quality" => ["QUALITY", "33333333-3333-4333-8333-%012d" % task_number]
    }.each do |review_key, (role, run_id)|
      review_path = File.join(reviews, "#{item_id}-#{review_key}.json")
      review_identities[review_key] = write_json(
        review_path,
        {
          "schema_version" => "strict-task-gate-review/v1",
          "reviewer_role" => role,
          "reviewer_identity" => "#{role} Fixture Reviewer #{task_number}",
          "reviewer_run_id" => run_id,
          "reviewed_at_utc" => "2026-07-28T12:00:00Z",
          "target_verdict" => "PASS",
          "task_id" => task_id,
          "required_item_id" => item_id,
          "candidate_commit" => commit,
          "candidate_tree" => tree,
          "evidence_manifest_sha256" => manifest.fetch("sha256")
        }
      )
    end
    receipt_path = File.join(audit, "#{item_id}-task-gate.json")
    receipt = write_json(
      receipt_path,
      {
        "schema_version" => "strict-task-gate-receipt/v1",
        "record_type" => "sourcelens_aios_strict_task_gate_receipt",
        "phase" => "P1",
        "task_id" => task_id,
        "required_item_id" => item_id,
        "decision" => "PASS",
        "accepted_commit" => commit,
        "accepted_tree" => tree,
        "evidence_manifest" => manifest,
        "reviews" => review_identities
      }
    )
    p1["required_items"][item_id] = {
      "status" => "ACCEPTED",
      "task_history_key" => history_key,
      "task_id" => task_id,
      "acceptance_commit" => commit,
      "acceptance_tree" => tree,
      "gate_evidence" => receipt.merge("receipt_type" => "STRICT_TASK_GATE_RECEIPT_V1")
    }
    truth["task_history"][history_key] = {
      "task_id" => task_id,
      "status" => "MASTER_TASK_GATE_ACCEPTED_COMPLETE",
      "accepted_candidate_commit" => commit,
      "accepted_candidate_tree" => tree
    }
  end

  decision_id = "P1-STRICT-EXIT-POSITIVE-FIXTURE"
  authorization_token = "AUTHORIZE_P1_STRICT_EXIT_POSITIVE_FIXTURE_V1"
  decision_path = File.join(attachment, "founder-decision.json")
  decision = write_json(
    decision_path,
    {
      "schema_version" => "strict-founder-phase-gate-decision/v1",
      "record_type" => "sourcelens_aios_strict_founder_phase_gate_decision",
      "authority" => "HUMAN_FOUNDER",
      "source_kind" => "FOUNDER_PROVIDED_CODEX_ATTACHMENT",
      "phase" => "P1",
      "decision" => "PASS",
      "decision_id" => decision_id,
      "authorization_token" => authorization_token,
      "canonical_commit" => commit,
      "canonical_tree" => tree
    }
  )
  item_receipts = p1.fetch("required_item_ids").to_h do |item_id|
    [item_id, p1.dig("required_items", item_id, "gate_evidence", "sha256")]
  end
  founder_receipt_path = File.join(audit, "founder-phase-gate.json")
  founder_receipt = write_json(
    founder_receipt_path,
    {
      "schema_version" => "strict-founder-phase-gate-receipt/v1",
      "record_type" => "sourcelens_aios_strict_founder_phase_gate_receipt",
      "phase" => "P1",
      "decision" => "PASS",
      "decision_id" => decision_id,
      "authorization_token" => authorization_token,
      "founder_decision" => decision,
      "required_item_receipts" => item_receipts,
      "canonical_commit" => commit,
      "canonical_tree" => tree
    }
  )
  p1["status"] = "COMPLETE"
  p1["derived_completion"] = {"completed" => 8, "total" => 8, "percent" => 100}
  p1["founder_phase_gate"] = founder_receipt.merge(
    "status" => "PASS",
    "decision_id" => decision_id
  )
  truth["p1_partial_exit"]["strict_completion"] = {"completed" => 8, "total" => 8, "percent" => 100}
  truth["p1_partial_exit"]["missing_exit_items"] = []
  truth["p1_partial_exit"]["phase_pass_claimed"] = true
  truth["p1_partial_exit"]["completion_100_percent_claimed"] = true
  truth["project"]["p1_execution_status"] = "COMPLETE_STRICT_8_OF_8_100_PERCENT"

  fixture_path = File.join(audit, "strict-p1-complete.yaml")
  File.binwrite(fixture_path, YAML.dump(truth))
  stdout, stderr, status = run_phase_fixture(fixture_path, "P2", "NONE", "ROUTE_ACTIVATION")
  raise "strict P1 completion positive fixture failed\n#{stdout}#{stderr}" unless status.success?

  truth["strict_phase_gate_ledger"]["phases"]["P1"]["required_items"]
    .fetch("REPRODUCIBLE_BASELINE_REPORT")
    .fetch("gate_evidence")["sha256"] = "0" * 64
  tampered_path = File.join(audit, "strict-p1-tampered.yaml")
  File.binwrite(tampered_path, YAML.dump(truth))
  _stdout, _stderr, tampered_status = run_phase_fixture(
    tampered_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "tampered Gate identity was accepted" if tampered_status.success?

  puts "STRICT_PHASE_GATE_TESTS: PASS p1_complete_to_p2_precheck=1 tamper_rejected=1"
ensure
  FileUtils.remove_entry_secure(audit) if File.exist?(audit)
  FileUtils.remove_entry_secure(reviews) if File.exist?(reviews)
  FileUtils.remove_entry_secure(attachment) if File.exist?(attachment)
end

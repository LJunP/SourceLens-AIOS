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
VAULT_ROOT = "/Users/lijunpeng/Documents/AIOS-Founder-Knowledge-Vault"

def identity(path)
  bytes = File.binread(path)
  {
    "path" => path,
    "byte_length" => bytes.bytesize,
    "sha256" => Digest::SHA256.hexdigest(bytes)
  }
end

def canonicalize(value)
  case value
  when Hash
    value.keys.sort.to_h { |key| [key, canonicalize(value.fetch(key))] }
  when Array
    value.map { |item| canonicalize(item) }
  else
    value
  end
end

def event_sha(event)
  Digest::SHA256.hexdigest(
    JSON.generate(canonicalize(event.reject { |key, _value| key == "event_sha256" }))
  )
end

def write_review(path, artifact, verdict)
  scope = {
    "current_canonical_file_consistency" => "PASS",
    "domain_scoped_authority_boundary" => "PASS",
    "exact_bytes_import_boundary" => "PASS",
    "fact_inference_unknown_separation" => verdict == "PASS" ? "PASS" : "NON_PASS",
    "founder_learning_usefulness" => "PASS",
    "secret_and_restricted_source_screen" => "PASS"
  }
  review = {
    "schema_version" => "founder-knowledge-review/v2",
    "reviewer_identity" => "Independent Knowledge State Fixture Reviewer",
    "reviewer_independence" => "INDEPENDENT_NON_IMPLEMENTER",
    "reviewed_at_utc" => "2026-07-28T11:30:00Z",
    "target_verdict" => verdict,
    "candidate" => artifact.merge("exact_identity_verified" => true),
    "review_scope" => scope,
    "findings" => verdict == "PASS" ? [] : ["fixture NON_PASS"],
    "verified_facts" => ["fixture identity verified"],
    "import_authorization" => {
      "authorized" => verdict == "PASS",
      "authorized_candidate_path" => artifact.fetch("path"),
      "authorized_sha256" => artifact.fetch("sha256"),
      "authorized_byte_length" => artifact.fetch("byte_length"),
      "exact_bytes_only" => true,
      "normalization_or_edit_before_import_allowed" => false,
      "authorization_scope" =>
        "Founder Knowledge Vault learning import only; no Truth, Git, Evidence, Task authority, Gate or capability effect."
    }
  }
  File.binwrite(path, JSON.pretty_generate(review) + "\n")
end

def run_fixture(path, expected_pass)
  stdout, stderr, status = Open3.capture3(
    VALIDATOR, "--test-knowledge-sync-fixture", path, chdir: ROOT
  )
  if status.success? != expected_pass
    raise "fixture verdict drifted: expected_pass=#{expected_pass}\n#{stdout}#{stderr}"
  end
end

truth = YAML.safe_load(
  File.binread(TRUTH),
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
base_event = truth.fetch("founder_knowledge_sync").fetch("events").first
source_commit = base_event.fetch("source_commit")
source_tree = base_event.fetch("source_tree")

audit_root = Dir.mktmpdir("founder-knowledge-sync-", "/private/tmp")
vault_root = Dir.mktmpdir("codex-knowledge-sync-", VAULT_ROOT)
begin
  artifact_path = File.join(audit_root, "artifact.md")
  File.binwrite(
    artifact_path,
    "# FACT\nStrict phase state test.\n\n# INFERENCE\nNone.\n\n# UNKNOWN\nNone.\n"
  )
  artifact = identity(artifact_path)

  snapshot_bytes, snapshot_stderr, snapshot_status = Open3.capture3(
    "git", "-C", ROOT, "show", "#{source_commit}:docs/aios/truth/project_state.yaml"
  )
  raise snapshot_stderr unless snapshot_status.success?
  snapshot_path = File.join(audit_root, "truth-snapshot.yaml")
  File.binwrite(snapshot_path, snapshot_bytes)

  review_path = File.join(audit_root, "review-pass.json")
  write_review(review_path, artifact, "PASS")
  review = identity(review_path)
  import_path = File.join(vault_root, "artifact.md")
  FileUtils.cp(artifact_path, import_path, preserve: true)
  vault_import = identity(import_path)

  imported_event_id = "FKS-20260728-KNOWLEDGE-STATE-IMPORTED-TEST"
  receipt_path = File.join(audit_root, "receipt.json")
  receipt = {
    "schema_version" => "founder-knowledge-import-receipt/v1",
    "event_id" => imported_event_id,
    "source_commit" => source_commit,
    "source_tree" => source_tree,
    "truth_sha256" => Digest::SHA256.hexdigest(snapshot_bytes),
    "truth_snapshot" => identity(snapshot_path),
    "artifact" => artifact,
    "review" => review.merge("verdict" => "PASS"),
    "vault_import" => vault_import,
    "exact_bytes_equal" => true,
    "recorded_at_utc" => "2026-07-28T11:31:00Z"
  }
  File.binwrite(receipt_path, JSON.pretty_generate(receipt) + "\n")
  imported_event = {
    "event_id" => imported_event_id,
    "trigger_type" => "TEST_FIXTURE",
    "occurred_at_utc" => "2026-07-28T11:29:00Z",
    "source_commit" => source_commit,
    "source_tree" => source_tree,
    "previous_event_sha256" => base_event.fetch("event_sha256"),
    "event_sha256" => nil,
    "status" => "IMPORTED",
    "rationale" => "Positive imported state fixture.",
    "engineering_blocking" => false,
    "artifact" => artifact,
    "review" => review,
    "vault_import" => vault_import,
    "receipt" => identity(receipt_path)
  }
  imported_event["event_sha256"] = event_sha(imported_event)
  imported_truth = Marshal.load(Marshal.dump(truth))
  imported_truth["founder_knowledge_sync"]["events"] = [base_event, imported_event]
  imported_truth["founder_knowledge_sync"]["latest_event_id"] = imported_event_id
  imported_truth_path = File.join(audit_root, "imported-truth.yaml")
  File.binwrite(imported_truth_path, YAML.dump(imported_truth))
  run_fixture(imported_truth_path, true)

  nonpass_review_path = File.join(audit_root, "review-nonpass.json")
  write_review(nonpass_review_path, artifact, "NON_PASS")
  nonpass_event_id = "FKS-20260728-KNOWLEDGE-STATE-NONPASS-TEST"
  nonpass_event = imported_event.merge(
    "event_id" => nonpass_event_id,
    "status" => "NON_PASS",
    "rationale" => "Positive NON_PASS state fixture.",
    "review" => identity(nonpass_review_path),
    "vault_import" => {"path" => nil, "byte_length" => nil, "sha256" => nil},
    "receipt" => {"path" => nil, "byte_length" => nil, "sha256" => nil},
    "event_sha256" => nil
  )
  nonpass_event["event_sha256"] = event_sha(nonpass_event)
  nonpass_truth = Marshal.load(Marshal.dump(truth))
  nonpass_truth["founder_knowledge_sync"]["events"] = [base_event, nonpass_event]
  nonpass_truth["founder_knowledge_sync"]["latest_event_id"] = nonpass_event_id
  nonpass_truth_path = File.join(audit_root, "nonpass-truth.yaml")
  File.binwrite(nonpass_truth_path, YAML.dump(nonpass_truth))
  run_fixture(nonpass_truth_path, true)

  outside_truth = Marshal.load(Marshal.dump(imported_truth))
  outside_import = identity(artifact_path)
  outside_event = outside_truth["founder_knowledge_sync"]["events"].last
  outside_event["vault_import"] = outside_import
  outside_event["event_sha256"] = event_sha(outside_event)
  outside_truth_path = File.join(audit_root, "outside-vault-truth.yaml")
  File.binwrite(outside_truth_path, YAML.dump(outside_truth))
  run_fixture(outside_truth_path, false)

  puts "FOUNDER_KNOWLEDGE_SYNC_TESTS: PASS imported=1 nonpass=1 outside_vault_rejected=1"
ensure
  FileUtils.remove_entry_secure(audit_root) if File.exist?(audit_root)
  FileUtils.remove_entry_secure(vault_root) if File.exist?(vault_root)
end

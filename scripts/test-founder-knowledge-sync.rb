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
def deep_copy(value)
  Marshal.load(Marshal.dump(value))
end

def compatibility_entry(truth, compatibility_type)
  truth.fetch("founder_knowledge_sync")
    .fetch("inherited_knowledge_compatibility")
    .fetch("entries")
    .find { |entry| entry.fetch("compatibility_type") == compatibility_type }
end

def rehash_events!(truth)
  sync = truth.fetch("founder_knowledge_sync")
  residual = compatibility_entry(
    truth, "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL"
  )
  previous = nil
  sync.fetch("events").each do |event|
    event["previous_event_sha256"] = previous
    if residual.fetch("event_ids").include?(event.fetch("event_id"))
      residual["calculated_event_sha256"] = event_sha(event)
    else
      event["event_sha256"] = event_sha(event)
    end
    previous = event.fetch("event_sha256")
  end
  sync["latest_event_id"] = sync.fetch("events").last.fetch("event_id")
end

def write_truth_fixture(root, label, fixture)
  fixture_root = File.join(root, label)
  Dir.mkdir(fixture_root)
  path = File.join(fixture_root, "project_state.yaml")
  File.binwrite(path, YAML.dump(fixture))
  path
end

def run_truth_case(root, label, fixture, expected_pass = false)
  run_fixture(write_truth_fixture(root, label, fixture), expected_pass)
end

def replace_compatibility_object!(truth, compatibility_type, object_path)
  object_identity = identity(object_path)
  entry = compatibility_entry(truth, compatibility_type)
  entry["object"] = object_identity.merge("file_type" => "REGULAR_FILE_NON_SYMLINK")
  field = compatibility_type == "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1" ? "receipt" : "review"
  entry.fetch("event_ids").each do |event_id|
    event = truth.fetch("founder_knowledge_sync").fetch("events")
      .find { |candidate| candidate.fetch("event_id") == event_id }
    event[field] = object_identity
  end
  rehash_events!(truth)
end

def write_json_fixture(root, label, object)
  path = File.join(root, "#{label}.json")
  File.binwrite(path, JSON.pretty_generate(object) + "\n")
  path
end

audit_root = Dir.mktmpdir("founder-knowledge-compatibility-", "/private/tmp")
negative_cases = 0
begin
  run_fixture(TRUTH, true)

  fixture = deep_copy(truth)
  fixture.fetch("founder_knowledge_sync").delete("inherited_knowledge_compatibility")
  run_truth_case(audit_root, "DECLARATION_MISSING", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  fixture.dig("founder_knowledge_sync", "inherited_knowledge_compatibility")["unexpected"] = false
  run_truth_case(audit_root, "DECLARATION_EXTRA", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  fixture.dig("founder_knowledge_sync", "inherited_knowledge_compatibility", "entries").reverse!
  run_truth_case(audit_root, "DECLARATION_REORDER", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  entries = fixture.dig("founder_knowledge_sync", "inherited_knowledge_compatibility", "entries")
  entries << deep_copy(entries.last)
  run_truth_case(audit_root, "DECLARATION_FIFTH_ENTRY", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  fixture.dig("founder_knowledge_sync", "inherited_knowledge_compatibility", "founder_packet", "sha256").sub!(/\A./, "0")
  run_truth_case(audit_root, "PACKET_IDENTITY_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  compatibility_entry(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1").dig("object")["file_type"] = "SYMLINK"
  run_truth_case(audit_root, "OBJECT_TYPE_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  compatibility_entry(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1")["object_schema_version"] = "founder-knowledge-review/v2"
  run_truth_case(audit_root, "SCHEMA_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  compatibility_entry(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1")["event_ids"] = [
    fixture.dig("founder_knowledge_sync", "events").first.fetch("event_id"),
    fixture.dig("founder_knowledge_sync", "events").last.fetch("event_id")
  ]
  run_truth_case(audit_root, "UNRELATED_EVENT_INJECTION", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  compatibility_entry(fixture, "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL")["stored_event_sha256"] = "0" * 64
  run_truth_case(audit_root, "STORED_EVENT_HASH_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  compatibility_entry(fixture, "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL")["calculated_event_sha256"] = "0" * 64
  run_truth_case(audit_root, "CALCULATED_EVENT_HASH_DRIFT", fixture)
  negative_cases += 1

  %w[path byte_length sha256].each do |field|
    fixture = deep_copy(truth)
    object = compatibility_entry(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1").fetch("object")
    object[field] = if field == "path"
                      File.join(audit_root, "missing-review.json")
                    elsif field == "byte_length"
                      object.fetch(field) + 1
                    else
                      "0" * 64
                    end
    run_truth_case(audit_root, "OBJECT_#{field.upcase}_DRIFT", fixture)
    negative_cases += 1
  end

  duplicate_yaml_root = File.join(audit_root, "DECLARATION_DUPLICATE_YAML_KEY")
  Dir.mkdir(duplicate_yaml_root)
  duplicate_yaml = File.binread(TRUTH).sub(
    "  inherited_knowledge_compatibility:\n    schema_version: \"1.0\"\n",
    "  inherited_knowledge_compatibility:\n    schema_version: \"1.0\"\n    schema_version: \"1.0\"\n"
  )
  duplicate_yaml_path = File.join(duplicate_yaml_root, "project_state.yaml")
  File.binwrite(duplicate_yaml_path, duplicate_yaml)
  run_fixture(duplicate_yaml_path, false)
  negative_cases += 1

  fixture = deep_copy(truth)
  review_event = fixture.fetch("founder_knowledge_sync").fetch("events").find do |event|
    event.fetch("event_id") == "FKS-20260801-P1-178-TERMINAL-KNOWLEDGE-REVIEW-PASS-V1"
  end
  review_event["status"] = "NON_PASS"
  rehash_events!(fixture)
  run_truth_case(audit_root, "EVENT_STATUS_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  import_event = fixture.fetch("founder_knowledge_sync").fetch("events").last
  import_event.dig("vault_import", "sha256").sub!(/\A./, "0")
  rehash_events!(fixture)
  run_truth_case(audit_root, "VAULT_IDENTITY_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  review_event = fixture.fetch("founder_knowledge_sync").fetch("events").find do |event|
    event.fetch("event_id") == "FKS-20260801-P1-178-TERMINAL-KNOWLEDGE-REVIEW-PASS-V1"
  end
  review_event.dig("artifact", "sha256").sub!(/\A./, "0")
  rehash_events!(fixture)
  run_truth_case(audit_root, "ARTIFACT_IDENTITY_DRIFT", fixture)
  negative_cases += 1

  p1_165_review_path = compatibility_entry(
    truth, "ALTERNATE_FOUNDER_KNOWLEDGE_REVIEW_V2"
  ).dig("object", "path")
  fixture = deep_copy(truth)
  p1_165_review = JSON.parse(File.binread(p1_165_review_path))
  p1_165_review["unexpected"] = false
  mutated_path = write_json_fixture(audit_root, "p1-165-review-extra", p1_165_review)
  replace_compatibility_object!(fixture, "ALTERNATE_FOUNDER_KNOWLEDGE_REVIEW_V2", mutated_path)
  run_truth_case(audit_root, "P1_165_REVIEW_OUTER_KEY_DRIFT", fixture)
  negative_cases += 1

  p1_178_review_path = compatibility_entry(
    truth, "FOUNDER_KNOWLEDGE_REVIEW_V1"
  ).dig("object", "path")
  fixture = deep_copy(truth)
  p1_178_review = JSON.parse(File.binread(p1_178_review_path))
  p1_178_review["knowledge_verdict"] = "NON_PASS"
  mutated_path = write_json_fixture(audit_root, "p1-178-review-verdict", p1_178_review)
  replace_compatibility_object!(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1", mutated_path)
  run_truth_case(audit_root, "P1_178_REVIEW_VERDICT_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  p1_178_review = JSON.parse(File.binread(p1_178_review_path))
  p1_178_review.fetch("authorization")["unexpected"] = false
  mutated_path = write_json_fixture(audit_root, "p1-178-review-nested-extra", p1_178_review)
  replace_compatibility_object!(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1", mutated_path)
  run_truth_case(audit_root, "P1_178_REVIEW_NESTED_KEY_DRIFT", fixture)
  negative_cases += 1

  fixture = deep_copy(truth)
  duplicate_review_path = File.join(audit_root, "p1-178-review-duplicate.json")
  duplicate_review = File.binread(p1_178_review_path).sub(
    "{\n", "{\n  \"schema_version\": \"founder-knowledge-review/v1\",\n"
  )
  File.binwrite(duplicate_review_path, duplicate_review)
  replace_compatibility_object!(fixture, "FOUNDER_KNOWLEDGE_REVIEW_V1", duplicate_review_path)
  run_truth_case(audit_root, "P1_178_REVIEW_DUPLICATE_JSON_KEY", fixture)
  negative_cases += 1

  p1_178_receipt_path = compatibility_entry(
    truth, "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1"
  ).dig("object", "path")
  fixture = deep_copy(truth)
  p1_178_receipt = JSON.parse(File.binread(p1_178_receipt_path))
  p1_178_receipt["bytes_equal"] = false
  mutated_path = write_json_fixture(audit_root, "p1-178-receipt-bytes-equal", p1_178_receipt)
  replace_compatibility_object!(fixture, "FOUNDER_KNOWLEDGE_IMPORT_RECEIPT_V1", mutated_path)
  run_truth_case(audit_root, "P1_178_RECEIPT_BYTES_EQUAL_DRIFT", fixture)
  negative_cases += 1

  p1_168_receipt_path = compatibility_entry(
    truth, "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL"
  ).dig("object", "path")
  fixture = deep_copy(truth)
  p1_168_receipt = JSON.parse(File.binread(p1_168_receipt_path))
  p1_168_receipt["status"] = "PASS"
  mutated_path = write_json_fixture(audit_root, "p1-168-terminal-status", p1_168_receipt)
  compatibility_entry(fixture, "EVENT_HASH_AND_PRE_CANDIDATE_RECEIPT_RESIDUAL")["object"] =
    identity(mutated_path).merge("file_type" => "REGULAR_FILE_NON_SYMLINK")
  run_truth_case(audit_root, "P1_168_TERMINAL_STATUS_DRIFT", fixture)
  negative_cases += 1

  outside_fixture = deep_copy(truth)
  outside_event = outside_fixture.fetch("founder_knowledge_sync").fetch("events").last
  outside_event["vault_import"] = identity(p1_178_review_path)
  rehash_events!(outside_fixture)
  run_truth_case(audit_root, "OUTSIDE_VAULT_IMPORT", outside_fixture)
  negative_cases += 1

  puts "FOUNDER_KNOWLEDGE_SYNC_TESTS: PASS exact_compatibility_objects=4 negative_cases=#{negative_cases} canonical_vault_writes=0"
ensure
  FileUtils.remove_entry_secure(audit_root) if File.exist?(audit_root)
end

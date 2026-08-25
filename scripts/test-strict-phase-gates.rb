#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "open3"
require "tmpdir"
require "yaml"
require_relative "validate-strict-phase-gates"

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

if ARGV == ["--p4-lifecycle-policy-only"]
  p4 = P4ProposalFirstControlledRealTaskRouteValidation
  p4.validate_lifecycle_policy!
  positive_transitions = 0
  p4::ALLOWED_LIFECYCLE_TRANSITIONS.each do |from, destinations|
    destinations.each do |to|
      p4.validate_lifecycle_transition!(from, to)
      positive_transitions += 1
    end
  end
  negative_transitions = [
    ["PREDECESSOR_RECEIPT_PENDING", "PRODUCT_TASK_ACTIVE"],
    ["FOUNDATION_TASK_ACTIVE", "PREDECESSOR_RECEIPT_PENDING"],
    ["FOUNDATION_ROUTE_TERMINAL_NON_PASS", "FOUNDATION_TASK_ACTIVE"],
    ["EVALUATION_ACCEPTED_PHASE_GATE_ELIGIBLE", "EVALUATION_TASK_ACTIVE"]
  ]
  negative_count = 0
  negative_transitions.each do |from, to|
    begin
      p4.validate_lifecycle_transition!(from, to)
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      negative_count += 1
      next
    end
    raise "P4 lifecycle policy accepted illegal transition #{from} -> #{to}"
  end
  profile_mutations = {
    "consumed reset" => lambda do |profiles, _transitions|
      profiles["FOUNDATION_ACCEPTED_PRODUCT_ELIGIBLE"]["consumed"] = 0
    end,
    "terminal Founder boundary removed" => lambda do |profiles, _transitions|
      profiles["PRODUCT_ROUTE_TERMINAL_NON_PASS"]["founder_required"] = false
    end,
    "two active stages" => lambda do |profiles, _transitions|
      profiles["PRODUCT_TASK_ACTIVE"]["stage_statuses"][2] = "ACTIVE"
    end,
    "terminal successor injected" => lambda do |_profiles, transitions|
      transitions["EVALUATION_ROUTE_TERMINAL_NON_PASS"] = ["EVALUATION_TASK_ACTIVE"]
    end
  }
  profile_mutations.each do |label, mutation|
    profiles = Marshal.load(Marshal.dump(p4::LIFECYCLE))
    transitions = Marshal.load(Marshal.dump(p4::ALLOWED_LIFECYCLE_TRANSITIONS))
    mutation.call(profiles, transitions)
    begin
      p4.validate_lifecycle_policy!(profiles, transitions)
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      negative_count += 1
      next
    end
    raise "P4 lifecycle policy accepted mutation: #{label}"
  end
  raise "P4 lifecycle positive edge count drift" unless positive_transitions == 10
  puts "P4_LIFECYCLE_POLICY_TESTS: PASS profiles=#{p4::LIFECYCLE.length} " \
       "positive_transitions=#{positive_transitions} negatives=#{negative_count}"
  exit 0
end

if ARGV == ["--p4-transition-correction-only"]
  receipt_path =
    P4ProposalFirstControlledRealTaskRouteValidation::PHASE_ENTRY_RECEIPT_PATH
  receipt_bytes = File.binread(receipt_path)
  receipt_identity = {
    "path" => receipt_path,
    "byte_length" => receipt_bytes.bytesize,
    "sha256" => Digest::SHA256.hexdigest(receipt_bytes)
  }
  transition =
    P4ProposalFirstControlledRealTaskRouteValidation.validate_transition_receipt!(
      ROOT, receipt_identity
    )
  raise "transition receipt did not bind the frozen strategic commit" unless
    transition["commit"] == "890c8ed081df95194cd65ad033b4be316151493e"

  strict_source = {
    "path" => "scripts/validate-strict-phase-gates.rb",
    "byte_length" => 825_299,
    "sha256" => "b633cf17d7345f12964231409034461661abed1dcc86f1197803203a4ca9e7e9"
  }
  P4ProposalFirstControlledRealTaskRouteValidation.validate_transition_source_identity!(
    ROOT, transition["commit"], strict_source, "transition strict-validator positive fixture"
  )
  source_drift = Marshal.load(Marshal.dump(strict_source))
  source_drift["sha256"] = "0" * 64
  source_negative_checks = 0
  begin
    P4ProposalFirstControlledRealTaskRouteValidation.validate_transition_source_identity!(
      ROOT, transition["commit"], source_drift, "transition strict-validator drift fixture"
    )
  rescue P4ProposalFirstControlledRealTaskRouteValidationError
    source_negative_checks += 1
  else
    raise "transition source binding accepted a false source hash"
  end

  correction_negative_checks = 0
  Dir.mktmpdir("p4-transition-correction-") do |tmp|
    fixture = File.join(tmp, "repo")
    _stdout, stderr, status = Open3.capture3(
      "git", "clone", "--shared", "--quiet", ROOT, fixture
    )
    raise "transition correction fixture clone failed: #{stderr}" unless status.success?
    [["user.name", "P4 Correction Fixture"],
     ["user.email", "p4-correction-fixture@example.invalid"]].each do |key, value|
      _stdout, stderr, status = Open3.capture3("git", "-C", fixture, "config", key, value)
      raise "transition correction fixture config failed: #{stderr}" unless status.success?
    end

    transition_commit = transition.fetch("commit")
    correction_paths =
      P4ProposalFirstControlledRealTaskRouteValidation::POST_INTEGRATION_CORRECTION_ALLOWLIST
    make_correction = lambda do |subject:, extra_path: nil, mode_drift: false|
      _stdout, stderr, status = Open3.capture3(
        "git", "-C", fixture, "switch", "--detach", "--quiet", transition_commit
      )
      raise "transition correction fixture switch failed: #{stderr}" unless status.success?
      correction_paths.each do |path|
        File.open(File.join(fixture, path), "ab") { |file| file.write("\n") }
      end
      if extra_path
        File.binwrite(File.join(fixture, extra_path), "unexpected\n")
      end
      Open3.capture3("git", "-C", fixture, "add", *correction_paths, *Array(extra_path))
      if mode_drift
        _stdout, stderr, status = Open3.capture3(
          "git", "-C", fixture, "update-index", "--chmod=+x", correction_paths.first
        )
        raise "transition correction fixture mode drift failed: #{stderr}" unless status.success?
      end
      _stdout, stderr, status = Open3.capture3(
        "git", "-C", fixture, "commit", "--quiet", "-m", subject
      )
      raise "transition correction fixture commit failed: #{stderr}" unless status.success?
      Open3.capture3("git", "-C", fixture, "rev-parse", "HEAD").first.strip
    end

    valid_correction = make_correction.call(
      subject:
        P4ProposalFirstControlledRealTaskRouteValidation::POST_INTEGRATION_CORRECTION_SUBJECT
    )
    P4ProposalFirstControlledRealTaskRouteValidation.validate_post_integration_correction_commit!(
      fixture, transition_commit, valid_correction
    )

    [
      ["wrong subject", {subject: "fix(aios): unrelated correction"}],
      ["extra path", {
        subject:
          P4ProposalFirstControlledRealTaskRouteValidation::POST_INTEGRATION_CORRECTION_SUBJECT,
        extra_path: "UNEXPECTED_CORRECTION_PATH"
      }],
      ["mode drift", {
        subject:
          P4ProposalFirstControlledRealTaskRouteValidation::POST_INTEGRATION_CORRECTION_SUBJECT,
        mode_drift: true
      }]
    ].each do |label, arguments|
      candidate = make_correction.call(**arguments)
      begin
        P4ProposalFirstControlledRealTaskRouteValidation.validate_post_integration_correction_commit!(
          fixture, transition_commit, candidate
        )
      rescue P4ProposalFirstControlledRealTaskRouteValidationError
        correction_negative_checks += 1
        next
      end
      raise "transition correction guard accepted #{label}"
    end
  end

  puts "P4_TRANSITION_CORRECTION_TESTS: PASS positive=3 " \
       "negatives=#{source_negative_checks + correction_negative_checks}"
  exit 0
end

if ARGV == ["--p3-strict-reentry-current-only"]
  truth = YAML.safe_load(
    File.binread(TRUTH),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  reentry = P3StrictCapabilityReentryRouteValidation
  raise "current Route is not P3 strict capability reentry" unless
    truth.dig("current_phase_route", "route_id") == reentry::ROUTE_ID &&
      truth.dig("current_phase_route", "semantic_schema_version") == reentry::SEMANTIC_SCHEMA
  state = reentry.validate_truth!(root: ROOT, truth: truth)
  raise "P3 strict reentry compatibility state drift" unless
    state == "P3_MTRO_PRODUCT_ELIGIBLE_NOT_ACTIVATED"

  string_root = P4ProposalFirstControlledRealTaskRouteValidation.normalize_repository_root!(ROOT)
  pathname_root = P4ProposalFirstControlledRealTaskRouteValidation.normalize_repository_root!(
    Pathname.new(ROOT)
  )
  raise "P4 shared root normalization diverges by input type" unless
    string_root == pathname_root && string_root == Pathname.new(ROOT).realpath
  root_negative = 0
  ["relative/root", Object.new].each do |invalid_root|
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.normalize_repository_root!(invalid_root)
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      root_negative += 1
      next
    end
    raise "P4 shared root normalization accepted #{invalid_root.inspect}"
  end

  mutations = {
    "semantic schema alias removed" => lambda do |candidate|
      candidate.dig("current_phase_route")["semantic_schema_version"] = "p3-false-route/v1"
    end,
    "P4 entry restored early" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P4")["entry_authorized"] = true
    end,
    "P4 execution started early" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P4")["execution_started"] = true
    end,
    "strict item self-accepted" => lambda do |candidate|
      item = reentry::STRICT_ITEMS.first
      candidate.dig(
        "strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
        "required_items", item
      )["status"] = "ACCEPTED"
    end,
    "historical accounting refunded" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "historical_consumed")["engineering_tasks"] = 0
    end,
    "reentry envelope expanded" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "limits")["engineering_tasks"] = 3
    end,
    "successor chain enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "anti_cycle")[
        "successor_replacement_normalization_closure_feasibility_remediation_allowed"
      ] = true
    end,
    "rejected lineage read enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "clean_room")[
        "rejected_p3_or_p4_lineage_read_compare_copy_restore_or_integrate"
      ] = true
    end,
    "decision identity drift" => lambda do |candidate|
      candidate.dig("current_phase_route", "founder_strategy_decision")["sha256"] = "0" * 64
    end,
    "false capability progress" => lambda do |candidate|
      candidate.dig("current_phase_route", "progress")["p3_strict_capability_percent"] = 100
    end,
    "third stage injected" => lambda do |candidate|
      candidate.dig("current_phase_route", "ordered_stages") <<
        Marshal.load(Marshal.dump(candidate.dig("current_phase_route", "ordered_stages").last))
    end
  }
  negative_count = 0
  mutations.each do |label, mutation|
    candidate = Marshal.load(Marshal.dump(truth))
    mutation.call(candidate)
    begin
      reentry.validate_truth!(root: ROOT, truth: candidate)
    rescue P3StrictCapabilityReentryRouteValidationError
      negative_count += 1
      next
    end
    raise "P3 strict reentry validator accepted mutation: #{label}"
  end
  raise "P3 strict reentry negative count drift" unless negative_count == mutations.length
  raise "P4 root-normalization negative count drift" unless root_negative == 2
  puts "P3_STRICT_REENTRY_TESTS: PASS current=1 negatives=#{negative_count} " \
       "p4_root_inputs=2 p4_root_negatives=#{root_negative}"
  exit 0
end

if ARGV == ["--p4-current-only"]
  truth = YAML.safe_load(
    File.binread(TRUTH),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  raise "current Route is not P4 proposal-first" unless
    truth.dig("current_phase_route", "schema_version") ==
      P4ProposalFirstControlledRealTaskRouteValidation::ROUTE_SCHEMA
  state = P4ProposalFirstControlledRealTaskRouteValidation.validate_truth!(
    root: ROOT, truth: truth
  )
  raise "P4 proposal-first current state drift" unless
    state == "NOT_STARTED_PREDECESSOR_RECEIPT_PENDING"

  mutations = {
    "receipt missing but project enters P4" => lambda do |candidate|
      candidate.dig("project")["current_phase"] = "P4"
    end,
    "receipt missing but P4 entry is authorized" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P4")["entry_authorized"] = true
    end,
    "receipt missing but P4 execution is started" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P4")["execution_started"] = true
    end,
    "receipt missing but Route reports F1 eligible" => lambda do |candidate|
      profile = P4ProposalFirstControlledRealTaskRouteValidation::LIFECYCLE.fetch(
        "FOUNDATION_ELIGIBLE_NOT_ACTIVATED"
      )
      route = candidate.fetch("current_phase_route")
      route["lifecycle_stage"] = "FOUNDATION_ELIGIBLE_NOT_ACTIVATED"
      route["status"] = profile.fetch("route_status")
      route["execution_status"] = profile.fetch("state")
      route["scheduling_status"] = profile.fetch("scheduling")
      route["next_eligible_action"] = profile.fetch("action")
      route["ordered_stages"].each_with_index do |stage, index|
        stage["status"] = profile.fetch("stage_statuses")[index]
      end
    end,
    "receipt missing but F1 stage is eligible" => lambda do |candidate|
      candidate.dig("current_phase_route", "ordered_stages", 0)["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "receipt missing but phase boundary permits Task creation" => lambda do |candidate|
      candidate.dig("phase_boundary")["task_creation_allowed"] = true
    end,
    "receipt missing but phase execution claim permits Task creation" => lambda do |candidate|
      candidate.dig("phase_execution_claim")["task_creation_allowed"] = true
    end,
    "receipt missing but P4 envelope capacity is usable" => lambda do |candidate|
      candidate.dig("phase_execution_envelope")["remaining_capacity_usable"] = true
    end,
    "P3 capability false acceptance" => lambda do |candidate|
      candidate.dig(
        "strict_phase_gate_ledger", "phases", "P3", "original_capability_gate"
      )["status"] = "ACCEPTED"
    end,
    "P3 current Gate item false acceptance" => lambda do |candidate|
      candidate.dig(
        "strict_phase_gate_ledger", "phases", "P3", "current_exit_gate", "required_items"
      ).values.first["status"] = "ACCEPTED"
    end,
    "closure audit removed" => lambda do |candidate|
      candidate.dig("current_phase_route", "closure_audit")["verdict"] = "NON_PASS"
    end,
    "P4 Product activated before F1" => lambda do |candidate|
      candidate.dig("current_phase_route", "ordered_stages", 1)["status"] = "ACTIVE"
    end,
    "system-under-test shell enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "system_under_test_permissions")["shell"] = true
    end,
    "system-under-test Docker enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "system_under_test_permissions")["docker"] = true
    end,
    "external network enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "external_effects")["network"] = true
    end,
    "rejected P3 lineage read enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "clean_room")["rejected_p3_lineage_read"] = true
    end,
    "P5 early entry enabled" => lambda do |candidate|
      candidate.dig("current_phase_route", "anti_cycle")["p5_early_entry_allowed"] = true
    end,
    "P4 strict Gate accepted before E1" => lambda do |candidate|
      candidate.dig(
        "strict_phase_gate_ledger", "phases", "P4", "required_items",
        "VERIFIED_PATCHES_ON_CONTROLLED_REAL_TASKS"
      )["status"] = "ACCEPTED"
    end,
    "P4 lifecycle self-reported accepted without receipts" => lambda do |candidate|
      profile = P4ProposalFirstControlledRealTaskRouteValidation::LIFECYCLE.fetch(
        "EVALUATION_ACCEPTED_PHASE_GATE_ELIGIBLE"
      )
      route = candidate.fetch("current_phase_route")
      route["lifecycle_stage"] = "EVALUATION_ACCEPTED_PHASE_GATE_ELIGIBLE"
      route["status"] = profile.fetch("route_status")
      route["execution_status"] = profile.fetch("state")
      route["scheduling_status"] = profile.fetch("scheduling")
      route["next_eligible_action"] = profile.fetch("action")
      route["ordered_stages"].each_with_index do |stage, index|
        stage["status"] = profile.fetch("stage_statuses")[index]
      end
    end,
    "P4 envelope reset" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "limits")["engineering_tasks"] = 4
    end,
    "Long-term Goal falsely completed" => lambda do |candidate|
      candidate.dig("goal")["long_term_goal_status"] = "COMPLETE"
    end,
    "Founder decision identity drift" => lambda do |candidate|
      candidate.dig("current_phase_route", "founder_strategy_decision")["sha256"] = "0" * 64
    end
  }
  mutations.each do |label, mutation|
    candidate = Marshal.load(Marshal.dump(truth))
    mutation.call(candidate)
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_truth!(
        root: ROOT, truth: candidate
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      next
    end
    raise "P4 proposal-first validator accepted mutation: #{label}"
  end
  global_compatibility_negative_checks = 0
  Dir.mktmpdir("p3-research-non-pass-global-compatibility-") do |tmp|
    positive_path = File.join(tmp, "positive.yaml")
    File.binwrite(positive_path, YAML.dump(truth))
    stdout, stderr, status = run_phase_fixture(
      positive_path, "P3", "NONE", "STATE_AUDIT"
    )
    raise "global P3 dual-conclusion positive fixture failed\n#{stdout}#{stderr}" unless
      status.success?
    stdout, stderr, status = run_phase_fixture(
      positive_path, "P4", "NONE", "ROUTE_ACTIVATION"
    )
    raise "global P4 predecessor positive fixture failed\n#{stdout}#{stderr}" unless
      status.success?

    global_mutations = {
      "legacy capability phase PASS" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3")["status"] = "COMPLETE"
      end,
      "research exit claims strict capability progress" => lambda do |candidate|
        candidate.dig(
          "strict_phase_gate_ledger", "phases", "P3", "research_exit"
        )["strict_execution_capability_percent"] = 1
      end,
      "original capability accepted" => lambda do |candidate|
        candidate.dig(
          "strict_phase_gate_ledger", "phases", "P3", "original_capability_gate"
        )["capability_accepted"] = true
      end,
      "current capability item accepted" => lambda do |candidate|
        candidate.dig(
          "strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
          "required_items"
        ).values.first["status"] = "ACCEPTED"
      end,
      "Founder dual-conclusion status drift" => lambda do |candidate|
        candidate.dig(
          "strict_phase_gate_ledger", "phases", "P3", "founder_phase_gate"
        )["status"] = "PASS"
      end,
      "Founder decision identity drift" => lambda do |candidate|
        candidate.dig(
          "strict_phase_gate_ledger", "phases", "P3", "founder_phase_gate"
        )["sha256"] = "0" * 64
      end,
      "closure audit identity drift" => lambda do |candidate|
        candidate.dig(
          "strict_phase_gate_ledger", "phases", "P3", "founder_phase_gate",
          "closure_audit"
        )["sha256"] = "0" * 64
      end
    }
    global_mutations.each do |label, mutation|
      candidate = Marshal.load(Marshal.dump(truth))
      mutation.call(candidate)
      fixture_path = File.join(tmp, "#{label.gsub(/[^A-Za-z0-9]+/, "-")}.yaml")
      File.binwrite(fixture_path, YAML.dump(candidate))
      _stdout, _stderr, status = run_phase_fixture(
        fixture_path, "P3", "NONE", "STATE_AUDIT"
      )
      raise "global governance compatibility accepted mutation: #{label}" if
        status.success?
      global_compatibility_negative_checks += 1
    end
  end
  helper_negative_checks = 0
  expected_testcase_ids =
    P4ProposalFirstControlledRealTaskRouteValidation.expected_p1_required_testcase_ids
  P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_required_case_matrix!(
    P4ProposalFirstControlledRealTaskRouteValidation::P1_REQUIRED_CASES,
    expected_testcase_ids,
    "P4 P1 required-case positive fixture"
  )
  mutated_cases = Marshal.load(
    Marshal.dump(P4ProposalFirstControlledRealTaskRouteValidation::P1_REQUIRED_CASES)
  )
  mutated_cases.delete("MALFORMED_PATCH_REJECTED")
  begin
    P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_required_case_matrix!(
      mutated_cases, expected_testcase_ids, "P4 P1 required-case negative fixture"
    )
  rescue P4ProposalFirstControlledRealTaskRouteValidationError
    helper_negative_checks += 1
  else
    raise "P4 P1 required-case matrix accepted a missing required case"
  end
  junit_required = expected_testcase_ids.fetch("focused_tests").first
  junit_class, junit_name = junit_required.split("#", 2)
  junit_pass =
    "<testsuite tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\">" \
    "<testcase classname=\"#{junit_class}\" name=\"#{junit_name}\"/></testsuite>"
  P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_junit_documents!(
    [junit_pass], 1, [junit_required], "P4 P1 JUnit positive fixture"
  )
  junit_mutants = {
    "missing required testcase" =>
      "<testsuite tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"0\">" \
      "<testcase classname=\"fixture.Other\" name=\"passes\"/></testsuite>",
    "required testcase skipped" =>
      "<testsuite tests=\"1\" failures=\"0\" errors=\"0\" skipped=\"1\">" \
      "<testcase classname=\"#{junit_class}\" name=\"#{junit_name}\">" \
      "<skipped/></testcase></testsuite>",
    "required testcase failed" =>
      "<testsuite tests=\"1\" failures=\"1\" errors=\"0\" skipped=\"0\">" \
      "<testcase classname=\"#{junit_class}\" name=\"#{junit_name}\">" \
      "<failure/></testcase></testsuite>",
    "required testcase errored" =>
      "<testsuite tests=\"1\" failures=\"0\" errors=\"1\" skipped=\"0\">" \
      "<testcase classname=\"#{junit_class}\" name=\"#{junit_name}\">" \
      "<error/></testcase></testsuite>"
  }
  junit_mutants.each do |label, xml|
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_junit_documents!(
        [xml], 1, [junit_required], "P4 P1 JUnit #{label} fixture"
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      helper_negative_checks += 1
      next
    end
    raise "P4 P1 JUnit guard accepted #{label}"
  end

  migration_path =
    P4ProposalFirstControlledRealTaskRouteValidation::CONDITIONAL_P1_MIGRATION_PATH
  P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_iff!(
    ["backend-spring/src/main/java/example/Proposal.java"], nil
  )
  P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_iff!(
    [migration_path], {"path" => "receipt"}
  )
  [
    [[migration_path], nil],
    [["backend-spring/src/main/java/example/Proposal.java"], {"path" => "receipt"}]
  ].each do |paths, receipt|
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_iff!(
        paths, receipt
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      helper_negative_checks += 1
      next
    end
    raise "P4 P1 schema-need iff accepted a mismatched migration/receipt pair"
  end

  Dir.mktmpdir("p4-p1-policy-fixture-") do |tmp|
    _stdout, stderr, status = Open3.capture3("git", "init", "--quiet", tmp)
    raise "P4 P1 fixture git init failed: #{stderr}" unless status.success?
    [["user.name", "P4 Fixture"], ["user.email", "p4-fixture@example.invalid"]].each do |key, value|
      _stdout, stderr, status = Open3.capture3("git", "-C", tmp, "config", key, value)
      raise "P4 P1 fixture git config failed: #{stderr}" unless status.success?
    end
    product_path =
      "backend-spring/src/main/java/com/sourcelens/module/autorepair/service/" \
      "AutoRepairPatchPolicy.java"
    FileUtils.mkdir_p(File.join(tmp, File.dirname(product_path)))
    File.binwrite(File.join(tmp, product_path), "final class AutoRepairPatchPolicy {}\n")
    Open3.capture3("git", "-C", tmp, "add", product_path)
    _stdout, stderr, status = Open3.capture3(
      "git", "-C", tmp, "commit", "--quiet", "-m", "base"
    )
    raise "P4 P1 fixture base commit failed: #{stderr}" unless status.success?
    base_commit = Open3.capture3("git", "-C", tmp, "rev-parse", "HEAD").first.strip

    evidence_root = File.join(tmp, "evidence")
    FileUtils.mkdir_p(evidence_root)
    task = {"task_id" => "P4-P1-FIXTURE", "nonce" => "p4-p1-fixture-v1",
            "evidence_root" => evidence_root}
    parent_tree = Open3.capture3(
      "git", "-C", tmp, "show", "-s", "--format=%T", base_commit
    ).first.strip
    activation_parent = {
      "commit" => base_commit, "tree" => parent_tree,
      "truth" => {"path" => "docs/aios/truth/project_state.yaml",
                  "byte_length" => 0, "sha256" => Digest::SHA256.hexdigest("")}
    }
    receipt_path = File.join(evidence_root, "pre-worker-schema-need.json")
    receipt = {
      "schema_version" => "p4-p1-pre-worker-schema-need/v1",
      "record_type" => "P4_P1_PRE_WORKER_SCHEMA_NEED", "verdict" => "PASS",
      "decision" => "MIGRATION_REQUIRED", "task_id" => task["task_id"],
      "nonce" => task["nonce"], "activation_parent" => activation_parent,
      "migration_path" => migration_path, "activation_parent_path_state" => "ABSENT",
      "required_constraints" =>
        P4ProposalFirstControlledRealTaskRouteValidation::P1_SCHEMA_NEED_CONSTRAINTS,
      "checked_at_utc" => "2026-08-24T00:00:00Z"
    }
    receipt_identity = write_json(receipt_path, receipt)
    File.chmod(0o444, receipt_path)
    P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_receipt!(
      tmp, receipt_identity, task, activation_parent
    )
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_receipt!(
        tmp, receipt_identity, task, activation_parent, "2026-08-23T23:59:59Z"
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      helper_negative_checks += 1
    else
      raise "P4 P1 schema receipt accepted a post-Contract checked_at timestamp"
    end
    writable_receipt_path = File.join(evidence_root, "writable-schema-need.json")
    writable_receipt_identity = write_json(writable_receipt_path, receipt)
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_receipt!(
        tmp, writable_receipt_identity, task, activation_parent
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      helper_negative_checks += 1
    else
      raise "P4 P1 schema receipt accepted writable Evidence"
    end
    invalid_receipt_path = File.join(evidence_root, "invalid-pre-worker-schema-need.json")
    invalid_receipt = Marshal.load(Marshal.dump(receipt))
    invalid_receipt["decision"] = "MIGRATION_NOT_REQUIRED"
    invalid_receipt_identity = write_json(invalid_receipt_path, invalid_receipt)
    File.chmod(0o444, invalid_receipt_path)
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_receipt!(
        tmp, invalid_receipt_identity, task, activation_parent
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      helper_negative_checks += 1
    else
      raise "P4 P1 pre-Worker schema receipt accepted a false migration decision"
    end

    File.binwrite(
      File.join(tmp, product_path),
      "final class AutoRepairPatchPolicy { boolean proposalOnly() { return true; } }\n"
    )
    Open3.capture3("git", "-C", tmp, "add", product_path)
    _stdout, stderr, status = Open3.capture3(
      "git", "-C", tmp, "commit", "--quiet", "-m", "harmless"
    )
    raise "P4 P1 fixture harmless commit failed: #{stderr}" unless status.success?
    harmless_commit = Open3.capture3("git", "-C", tmp, "rev-parse", "HEAD").first.strip
    P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_forbidden_added_references!(
      tmp, base_commit, harmless_commit, [product_path]
    )

    previous_commit = harmless_commit
    P4ProposalFirstControlledRealTaskRouteValidation::P1_FORBIDDEN_ADDED_REFERENCES.each do |token|
      File.binwrite(
        File.join(tmp, product_path),
        "final class AutoRepairPatchPolicy { boolean proposalOnly() { return true; } } " \
        "// #{token}\n"
      )
      Open3.capture3("git", "-C", tmp, "add", product_path)
      _stdout, stderr, status = Open3.capture3(
        "git", "-C", tmp, "commit", "--quiet", "-m", "forbidden #{token}"
      )
      raise "P4 P1 fixture forbidden commit failed: #{stderr}" unless status.success?
      forbidden_commit = Open3.capture3(
        "git", "-C", tmp, "rev-parse", "HEAD"
      ).first.strip
      begin
        P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_forbidden_added_references!(
          tmp, previous_commit, forbidden_commit, [product_path]
        )
      rescue P4ProposalFirstControlledRealTaskRouteValidationError
        helper_negative_checks += 1
      else
        raise "P4 P1 forbidden-reference guard accepted #{token}"
      end
      previous_commit = forbidden_commit
    end

    FileUtils.mkdir_p(File.join(tmp, File.dirname(migration_path)))
    File.binwrite(File.join(tmp, migration_path), "-- proposal state\n")
    Open3.capture3("git", "-C", tmp, "add", migration_path)
    _stdout, stderr, status = Open3.capture3(
      "git", "-C", tmp, "commit", "--quiet", "-m", "migration already present"
    )
    raise "P4 P1 fixture migration commit failed: #{stderr}" unless status.success?
    migration_parent_commit = Open3.capture3(
      "git", "-C", tmp, "rev-parse", "HEAD"
    ).first.strip
    migration_parent = Marshal.load(Marshal.dump(activation_parent))
    migration_parent["commit"] = migration_parent_commit
    migration_parent["tree"] = Open3.capture3(
      "git", "-C", tmp, "show", "-s", "--format=%T", migration_parent_commit
    ).first.strip
    migration_present_receipt = Marshal.load(Marshal.dump(receipt))
    migration_present_receipt["activation_parent"] = migration_parent
    migration_present_path = File.join(evidence_root, "migration-present-schema-need.json")
    migration_present_identity = write_json(migration_present_path, migration_present_receipt)
    File.chmod(0o444, migration_present_path)
    begin
      P4ProposalFirstControlledRealTaskRouteValidation.validate_p1_schema_need_receipt!(
        tmp, migration_present_identity, task, migration_parent
      )
    rescue P4ProposalFirstControlledRealTaskRouteValidationError
      helper_negative_checks += 1
    else
      raise "P4 P1 schema receipt accepted a migration already present at activation parent"
    end
  end
  puts "STRICT_PHASE_GATE_TESTS: PASS p4_current=1 " \
       "p4_negative_mutations=#{mutations.length + helper_negative_checks + global_compatibility_negative_checks}"
  exit 0
end

if ARGV == ["--mtro-current-only"]
  truth = YAML.safe_load(
    File.binread(TRUTH),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  raise "current Route is not P3 MTRO" unless
    truth.dig("current_phase_route", "schema_version") ==
      P3MinimumTrustTransactionalOciFinalProductRouteValidation::ROUTE_SCHEMA
  state = P3MinimumTrustTransactionalOciFinalProductRouteValidation.validate_truth!(
    root: ROOT, truth: truth
  )
  expected_state =
    P3MinimumTrustTransactionalOciFinalProductRouteValidation::LIFECYCLE_PROFILES.fetch(
      truth.dig("current_phase_route", "lifecycle_stage")
    ).fetch("state")
  raise "P3 MTRO current state drift" unless state == expected_state

  mutations = {
    "old F2 rescheduled" => lambda do |candidate|
      candidate.dig("current_phase_route", "ordered_stages", 0)["task_id"] =
        "AIOS-P3-TRIVS-F2_CANDIDATE_BOUND_ACCEPTANCE_HARNESS"
    end,
    "budget reset" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "consumed")["engineering_tasks"] = 17
    end,
    "future daemon identity prefilled" => lambda do |candidate|
      channel = candidate.dig("current_phase_route", "runtime_identity_channel")
      channel["status"] = "PENDING_TASK_OWNED_DISCOVERY"
      channel[
        "task_activation_record"
      ] = {"daemon_id" => "future-daemon"}
    end,
    "strict Gate false acceptance" => lambda do |candidate|
      candidate.dig(
        "strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
        "required_items",
        "ACTUAL_AGENT_NON_AUTHORITATIVE_PROPOSAL_AND_EXCLUSIVE_RESERVED_INGRESS"
      )["status"] = "ACCEPTED"
    end,
    "second stage injected" => lambda do |candidate|
      candidate.dig("current_phase_route", "ordered_stages") <<
        Marshal.load(Marshal.dump(candidate.dig("current_phase_route", "ordered_stages", 0)))
    end,
    "P4 entered early" => lambda do |candidate|
      candidate.dig("project")["current_phase"] = "P4"
    end,
    "clean-room rejected lineage reopened" => lambda do |candidate|
      candidate.dig("current_phase_route", "clean_room")[
        "rejected_trivs_candidate_1_or_old_dtk_etsk_twrf_engineering_lineage_read_compare_copy_execute_decompile_restore_repair_or_reuse"
      ] = true
    end,
    "local OCI authority effective before Task" => lambda do |candidate|
      candidate.dig("current_phase_route", "local_external_effect_authority")[
        "effective_only_after_task_active"
      ] = false
    end,
    "anti-cycle successor reopened" => lambda do |candidate|
      candidate.dig("current_phase_route", "anti_cycle")[
        "successor_replacement_normalization_closure_feasibility_remediation_allowed"
      ] = true
    end,
    "boundary network capability exposed" => lambda do |candidate|
      candidate.dig("phase_boundary", "default_external_effects")["network"] = true
    end,
    "boundary worker root made unrestricted" => lambda do |candidate|
      candidate.dig("phase_boundary", "role_write_roots")["worker"] = ["/"]
    end,
    "active-work remote effect exposed" => lambda do |candidate|
      candidate.dig("active_work", "external_effects")["remote"] = true
    end,
    "Goal Task authority fabricated" => lambda do |candidate|
      candidate.dig("goal")["current_task_authority"] = "FABRICATED_AUTHORITY"
    end,
    "envelope authority source drift" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "authority_basis")["source_route_id"] =
        "UNDECLARED_ROUTE"
    end,
    "envelope accounting made resettable" => lambda do |candidate|
      candidate.dig("phase_execution_envelope")["accounting_basis"] =
        "RESETTABLE_PER_TASK"
    end,
    "envelope stage lifecycle drift" => lambda do |candidate|
      stage = candidate.dig("phase_execution_envelope", "ordered_stages", 0)
      stage["status"] = stage["status"] == "ACTIVE" ? "ELIGIBLE_NOT_ACTIVATED" : "ACTIVE"
    end,
    "envelope external network exposed" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "external_effects")["network"] = true
    end,
    "compatibility accepted without current Gate" => lambda do |candidate|
      candidate.dig(
        "strict_phase_gate_ledger", "phases", "P3", "required_items",
        "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"
      )["status"] = "ACCEPTED"
    end,
    "product architecture generic registry reopened" => lambda do |candidate|
      candidate.dig("current_phase_route", "product_architecture")[
        "generic_tool_registry_bypassed"
      ] = false
    end,
    "long-term Goal lifecycle falsely completed" => lambda do |candidate|
      candidate.dig("current_phase_route", "lifecycle")["long_term_goal_status"] = "COMPLETE"
    end,
    "accepted lifecycle self-reported without Evidence" => lambda do |candidate|
      profile =
        P3MinimumTrustTransactionalOciFinalProductRouteValidation::LIFECYCLE_PROFILES.fetch(
          "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE"
        )
      route = candidate["current_phase_route"]
      route["lifecycle_stage"] = "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE"
      route["status"] = profile.fetch("route_status")
      route["execution_status"] = profile.fetch("state")
      route["scheduling_status"] = profile.fetch("scheduling_status")
      route["ordered_stages"][0]["status"] = profile.fetch("stage_status")
      route["next_eligible_action"] = profile.fetch("action")
      route["progress"] = {
        "delivery_percent" => 100, "strict_exit_percent" => 100,
        "governance_progress_credit" => 0
      }
    end,
    "claim current Task drift" => lambda do |candidate|
      candidate.dig("claim_boundary")["current_task"] = "FABRICATED_TASK"
    end,
    "claim selected Task drift" => lambda do |candidate|
      candidate.dig("claim_boundary")["selected_task"] = "NONE"
    end,
    "claim next action drift" => lambda do |candidate|
      candidate.dig("claim_boundary")["next_eligible_action"] = "FOUNDER_DECIDE_P3_PHASE_GATE"
    end,
    "claim Founder trigger drift" => lambda do |candidate|
      candidate.dig("claim_boundary")["founder_reserved_trigger"] = "PHASE_ENTRY_OR_EXIT"
    end,
    "claim Long-term Goal closed" => lambda do |candidate|
      candidate.dig("claim_boundary")["long_term_goal_status"] = "COMPLETE"
    end,
    "claim executable slots reset" => lambda do |candidate|
      candidate.dig("claim_boundary")["current_route_executable_task_slots"] =
        "2_OF_2_ELIGIBLE"
    end,
    "claim Product milestone accepted early" => lambda do |candidate|
      candidate.dig("claim_boundary", "p3_accepted_milestones") <<
        "ACTUAL_AGENT_TRANSACTIONAL_OCI_READ_ONLY_INVOCATION_PRODUCT"
    end,
    "claim capability accepted early" => lambda do |candidate|
      candidate.dig("claim_boundary")["p3_capability_milestone_status"] =
        "ACCEPTED_NARROW_MTRO_SLICE"
    end,
    "claim project complete engineering" => lambda do |candidate|
      candidate.dig("claim_boundary")["real_engineering_progress"] = "PROJECT_COMPLETE"
    end,
    "project Phase name drift" => lambda do |candidate|
      candidate.dig("project")["phase_name"] = "P4"
    end,
    "project canonical branch drift" => lambda do |candidate|
      candidate.dig("project")["canonical_branch"] = "develop"
    end,
    "Goal identity drift" => lambda do |candidate|
      candidate.dig("goal")["identity_status"] = "COMPLETE"
    end,
    "Goal state note drift" => lambda do |candidate|
      candidate.dig("goal")["current_state_note"] = "project complete"
    end,
    "terminal basis future scheduling injection" => lambda do |candidate|
      candidate.dig("current_phase_route", "terminal_basis")["future_scheduling_authority"] = true
    end,
    "Route engineering progress injected" => lambda do |candidate|
      candidate.dig("current_phase_route", "progress")["engineering_progress_credit"] = 100
    end,
    "P3 Phase entry decision drift" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "phase_entry_decision")[
        "decision_id"
      ] = "FABRICATED_PHASE_ENTRY"
    end,
    "P3 Exit Gate authority drift" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "exit_gate_authority")[
        "source"
      ] = "SELF_REPORT"
    end,
    "Phase execution claim Task drift" => lambda do |candidate|
      candidate.dig("phase_execution_claim")["current_task_claim"] = "FABRICATED_TASK"
    end,
    "Phase execution claim integration opened early" => lambda do |candidate|
      candidate.dig("phase_execution_claim")["candidate_integration_allowed"] = true
    end
  }
  mutations.each do |label, mutation|
    candidate = Marshal.load(Marshal.dump(truth))
    mutation.call(candidate)
    begin
      P3MinimumTrustTransactionalOciFinalProductRouteValidation.validate_truth!(
        root: ROOT, truth: candidate
      )
    rescue P3MinimumTrustTransactionalOciFinalProductRouteValidationError
      next
    end
    raise "P3 MTRO validator accepted mutation: #{label}"
  end
  lifecycle_channel = {
    "status" => "INTEGRATED_REPLAY_BOUND",
    "task_activation_record" => {"path" => "/not-read", "byte_length" => 0, "sha256" => "0" * 64},
    "candidate_freeze_record" => {"path" => "/not-read", "byte_length" => 0, "sha256" => "0" * 64},
    "review_dispatch_record" => {"path" => "/not-read", "byte_length" => 0, "sha256" => "0" * 64},
    "integration_record" => {"path" => "/not-read", "byte_length" => 0, "sha256" => "0" * 64},
    "canonical_replay_record" => {"path" => "/not-read", "byte_length" => 0, "sha256" => "0" * 64},
    "future_dynamic_identity_prefill_allowed" => false
  }
  %w[PRODUCT_TASK_ACTIVE PRODUCT_ROUTE_TERMINAL_NON_PASS].each do |lifecycle|
    begin
      P3MinimumTrustTransactionalOciFinalProductRouteValidation.validate_runtime_identity_channel!(
        ROOT, lifecycle_channel, lifecycle
      )
    rescue P3MinimumTrustTransactionalOciFinalProductRouteValidationError
      next
    end
    raise "P3 MTRO #{lifecycle} accepted integrated runtime state"
  end
  begin
    P3MinimumTrustTransactionalOciFinalProductRouteValidation.validate_runtime_identity_channel!(
      ROOT, lifecycle_channel, "PRODUCT_ACCEPTED_PHASE_GATE_ELIGIBLE"
    )
  rescue P3MinimumTrustTransactionalOciFinalProductRouteValidationError
    # Missing replay records/raw bundle must fail before accepted state can be trusted.
  else
    raise "P3 MTRO accepted lifecycle passed without a replay raw bundle"
  end
  raw_fail_projection =
    P3MinimumTrustTransactionalOciFinalProductRouteValidation.derive_fact_projection!(
      root: ROOT,
      fact_id: "CHECKPOINT_BEFORE_TERMINAL_REJECTED",
      events: [
        {"event_type" => "TERMINAL_STATE", "payload" => {"committed" => true}},
        {"event_type" => "CHECKPOINT_ATTEMPT", "payload" => {"result" => "ACCEPTED"}},
        {"event_type" => "CHECKPOINT_ROW_COUNT", "payload" => {"count" => 1}}
      ],
      candidate: {},
      activation_identity: nil
    )
  raise "P3 MTRO raw FAIL projected checkpoint PASS" unless
    raw_fail_projection["result"] == "NON_PASS"
  raw_observer = JSON.generate(
    {
      "schema_version" => "p3-mtro-external-effect-raw-observation/v1",
      "record_type" => "P3_MTRO_EXTERNAL_EFFECT_RAW_OBSERVATION",
      "effect" => "internet",
      "observer" => "TASK_SCOPED_OS_AND_PROCESS_OBSERVER",
      "argv" => ["observer", "internet"],
      "observed_events" => ["connect 203.0.113.1:443"],
      "observation_started_at_utc" => "2026-08-24T00:00:00Z",
      "observation_finished_at_utc" => "2026-08-24T00:00:01Z"
    }
  )
  observed =
    P3MinimumTrustTransactionalOciFinalProductRouteValidation
      .derive_external_effect_observation!(raw_observer, "internet", "observer mutant")
  raise "P3 MTRO raw observed effect projected false" unless observed["observed"] == true
  invocation_sha256 = "a" * 64
  oci_argv = [
    P3MinimumTrustTransactionalOciFinalProductRouteValidation::DOCKER_CLI.fetch("path"),
    "--host", P3MinimumTrustTransactionalOciFinalProductRouteValidation::DOCKER_ENDPOINT,
    "create", "--name", "sourcelens-mtro-#{invocation_sha256}",
    "--label", "com.sourcelens.task_id=#{P3MinimumTrustTransactionalOciFinalProductRouteValidation::TASK_ID}",
    "--label", "com.sourcelens.invocation_sha256=#{invocation_sha256}",
    "--user", "65534:65534", "--network", "none", "--read-only", "--cap-drop", "ALL",
    "--security-opt", "no-new-privileges", "--cpus", "1", "--memory", "256m",
    "--pids-limit", "64", "--mount",
    "type=bind,source=/private/tmp/#{invocation_sha256},target=/input/custody.bin,readonly",
    "--entrypoint", "/usr/bin/sha256sum",
    P3MinimumTrustTransactionalOciFinalProductRouteValidation::IMAGE_ID, "/input/custody.bin"
  ]
  malicious_inspect = JSON.generate(
    [{
      "Id" => "b" * 64, "Name" => "/sourcelens-mtro-#{invocation_sha256}",
      "Image" => P3MinimumTrustTransactionalOciFinalProductRouteValidation::IMAGE_ID,
      "Config" => {
        "Image" => P3MinimumTrustTransactionalOciFinalProductRouteValidation::IMAGE_ID,
        "Labels" => {
          "com.sourcelens.task_id" => P3MinimumTrustTransactionalOciFinalProductRouteValidation::TASK_ID,
          "com.sourcelens.invocation_sha256" => invocation_sha256
        },
        "User" => "65534:65534", "Entrypoint" => ["/usr/bin/sha256sum"],
        "Cmd" => ["/input/custody.bin"]
      },
      "HostConfig" => {
        "Privileged" => false, "Binds" => nil, "CapAdd" => nil, "NetworkMode" => "host",
        "ReadonlyRootfs" => false, "Memory" => 0, "NanoCpus" => 0, "PidsLimit" => 0,
        "CapDrop" => [], "SecurityOpt" => []
      },
      "Mounts" => [{
        "Type" => "bind", "Source" => "/private/tmp/#{invocation_sha256}",
        "Destination" => "/input/custody.bin", "RW" => false
      }],
      "State" => {"ExitCode" => 0}
    }]
  )
  begin
    P3MinimumTrustTransactionalOciFinalProductRouteValidation.validate_mtro_oci_inspect!(
      inspect_bytes: malicious_inspect, argv: oci_argv, exit_code: 0
    )
  rescue P3MinimumTrustTransactionalOciFinalProductRouteValidationError
    # A claimed PASS backed by a host-network, writable-root container must fail closed.
  else
    raise "P3 MTRO OCI inspect accepted a foreign isolation profile"
  end
  exact_file =
    "backend-spring/src/main/java/com/sourcelens/module/agent/service/AgentRuntime.java"
  if P3MinimumTrustTransactionalOciFinalProductRouteValidation.path_covered_by_allowlist?(
       "#{exact_file}/Injected.java", [exact_file]
     )
    raise "P3 MTRO exact-file allowlist accepted a child path"
  end
  Dir.mktmpdir("p3-mtro-path-guard-") do |tmp|
    real_root = File.join(tmp, "real")
    symlink_root = File.join(tmp, "alias")
    FileUtils.mkdir_p(real_root)
    File.symlink(real_root, symlink_root)
    begin
      P3MinimumTrustTransactionalOciFinalProductRouteValidation.literal_path!(
        Pathname.new(symlink_root), "P3 MTRO symlink-root mutant", directory: true
      )
    rescue P3MinimumTrustTransactionalOciFinalProductRouteValidationError
      next
    end
    raise "P3 MTRO literal-root guard accepted a symlink"
  end
  puts "STRICT_PHASE_GATE_TESTS: PASS mtro_current=1 negatives=#{mutations.length + 8}"
  exit 0
elsif ARGV == ["--etsk-current-only"]
  truth = YAML.safe_load(
    File.binread(TRUTH),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  raise "current Route is not P3 ETSK" unless
    truth.dig("current_phase_route", "schema_version") ==
      P3ExecutableTransitionSystemKernelRouteValidation::ROUTE_SCHEMA
  state = P3ExecutableTransitionSystemKernelRouteValidation.validate_truth!(root: ROOT, truth: truth)
  expected = P3ExecutableTransitionSystemKernelRouteValidation::LIFECYCLE_STATES.fetch(
    truth.dig("current_phase_route", "lifecycle_stage")
  )
  raise "ETSK strict Gate current state drift" unless state == expected
  mutations = {
    "task-wide item removal" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                    "required_item_ids").delete("TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER")
    end,
    "task-wide item false acceptance" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                    "required_items", "TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER")["status"] =
        "ACCEPTED"
    end,
    "compatibility projection false acceptance" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                    "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
    end,
    "strict Gate candidate split" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate")[
        "same_frozen_candidate_required"
      ] = false
    end,
    "P4 premature entry" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end
  }
  mutations.each do |label, mutation|
    candidate = JSON.parse(JSON.generate(truth))
    begin
      mutation.call(candidate)
      P3ExecutableTransitionSystemKernelRouteValidation.validate_truth!(root: ROOT, truth: candidate)
      raise "ETSK strict Gate mutation false-PASSed: #{label}"
    rescue P3ExecutableTransitionSystemKernelRouteValidationError
      # expected
    end
  end
  puts "STRICT_PHASE_GATE_TESTS: PASS etsk_current=1 etsk_negative_mutations=#{mutations.length}"
  exit 0
end

if ARGV == ["--dtk-current-only"]
  truth = YAML.safe_load(
    File.binread(TRUTH),
    permitted_classes: [],
    permitted_symbols: [],
    aliases: false
  )
  raise "current Route is not P3 DTK" unless
    truth.dig("current_phase_route", "schema_version") ==
      P3DeclarativeTransactionKernelRouteValidation::ROUTE_SCHEMA
  state = P3DeclarativeTransactionKernelRouteValidation.validate_truth!(root: ROOT, truth: truth)
  expected = P3DeclarativeTransactionKernelRouteValidation::LIFECYCLE_STATES.fetch(
    truth.dig("current_phase_route", "lifecycle_stage")
  )
  raise "DTK strict Gate current state drift" unless state == expected
  mutations = {
    "declarative semantic item removal" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                    "required_item_ids").delete(
                      "DECLARATIVE_TRANSITION_SEMANTIC_INTEGRITY_AND_INDEPENDENT_REPLAY"
                    )
    end,
    "declarative semantic item false acceptance" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                    "required_items",
                    "DECLARATIVE_TRANSITION_SEMANTIC_INTEGRITY_AND_INDEPENDENT_REPLAY")["status"] =
        "ACCEPTED"
    end,
    "compatibility projection false acceptance" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                    "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
    end,
    "strict Gate candidate split" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate")[
        "same_frozen_candidate_required"
      ] = false
    end,
    "P4 premature entry" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end
  }
  mutations.each do |label, mutation|
    candidate = JSON.parse(JSON.generate(truth))
    begin
      mutation.call(candidate)
      P3DeclarativeTransactionKernelRouteValidation.validate_truth!(root: ROOT, truth: candidate)
      raise "DTK strict Gate mutation false-PASSed: #{label}"
    rescue P3DeclarativeTransactionKernelRouteValidationError
      # expected
    end
  end
  puts "STRICT_PHASE_GATE_TESTS: PASS dtk_current=1 dtk_negative_mutations=#{mutations.length}"
  exit 0
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
  if truth.dig("current_phase_route", "schema_version") ==
     P3ExecutableTransitionSystemKernelRouteValidation::ROUTE_SCHEMA
    state = P3ExecutableTransitionSystemKernelRouteValidation.validate_truth!(root: ROOT, truth: truth)
    expected = P3ExecutableTransitionSystemKernelRouteValidation::LIFECYCLE_STATES.fetch(
      truth.dig("current_phase_route", "lifecycle_stage")
    )
    raise "ETSK strict Gate current state drift" unless state == expected
    {
      "task-wide item removal" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                      "required_item_ids").delete("TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER")
      end,
      "task-wide item false acceptance" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                      "required_items", "TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER")["status"] =
          "ACCEPTED"
      end,
      "compatibility projection false acceptance" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                      "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
      end,
      "strict Gate candidate split" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate")[
          "same_frozen_candidate_required"
        ] = false
      end,
      "P4 premature entry" => lambda do |candidate|
        candidate["project"]["p4_entry_status"] = "AUTHORIZED"
      end
    }.each do |label, mutation|
      candidate = JSON.parse(JSON.generate(truth))
      begin
        mutation.call(candidate)
        P3ExecutableTransitionSystemKernelRouteValidation.validate_truth!(root: ROOT, truth: candidate)
        raise "ETSK strict Gate mutation false-PASSed: #{label}"
      rescue P3ExecutableTransitionSystemKernelRouteValidationError
        # expected
      end
    end
  end
  if truth.dig("current_phase_route", "schema_version") ==
     P3DeclarativeTransactionKernelRouteValidation::ROUTE_SCHEMA
    state = P3DeclarativeTransactionKernelRouteValidation.validate_truth!(root: ROOT, truth: truth)
    expected = P3DeclarativeTransactionKernelRouteValidation::LIFECYCLE_STATES.fetch(
      truth.dig("current_phase_route", "lifecycle_stage")
    )
    raise "DTK strict Gate current state drift" unless state == expected
    {
      "declarative semantic item removal" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                      "required_item_ids").delete(
                        "DECLARATIVE_TRANSITION_SEMANTIC_INTEGRITY_AND_INDEPENDENT_REPLAY"
                      )
      end,
      "declarative semantic item false acceptance" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                      "required_items",
                      "DECLARATIVE_TRANSITION_SEMANTIC_INTEGRITY_AND_INDEPENDENT_REPLAY")["status"] =
          "ACCEPTED"
      end,
      "compatibility projection false acceptance" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                      "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
      end,
      "strict Gate candidate split" => lambda do |candidate|
        candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate")[
          "same_frozen_candidate_required"
        ] = false
      end,
      "P4 premature entry" => lambda do |candidate|
        candidate["project"]["p4_entry_status"] = "AUTHORIZED"
      end
    }.each do |label, mutation|
      candidate = JSON.parse(JSON.generate(truth))
      begin
        mutation.call(candidate)
        P3DeclarativeTransactionKernelRouteValidation.validate_truth!(root: ROOT, truth: candidate)
        raise "DTK strict Gate mutation false-PASSed: #{label}"
      rescue P3DeclarativeTransactionKernelRouteValidationError
        # expected
      end
    end
  end
  # This matrix exercises the P1 -> P2 boundary even after canonical execution
  # has entered P2. Isolate that lifecycle from the live Phase and active Task
  # instead of implicitly assuming canonical current_phase == P1.
  truth.fetch("project")["current_phase"] = "P1"
  truth.fetch("project")["p2_entry_status"] = "HOLD_PENDING_FOUNDER_PHASE_ENTRY"
  truth.fetch("project")["p2_execution_status"] = "HOLD_PENDING_FOUNDER_PHASE_ENTRY"
  truth.fetch("project")["p3_entry_status"] = "HOLD_PENDING_STRICT_P2_EXIT"
  truth.fetch("project")["p3_execution_status"] = "HOLD_PENDING_STRICT_P2_EXIT"
  truth.fetch("project")["p4_entry_status"] = "HOLD_PENDING_STRICT_P3_EXIT"
  truth.fetch("current_phase_route")["phase"] = "P1"
  truth.fetch("goal")["current_task_authority"] = "NONE"
  truth.fetch("active_work")["current_task"] = "NONE"
  commit, commit_stderr, commit_status = Open3.capture3("git", "-C", ROOT, "rev-parse", "HEAD")
  raise commit_stderr unless commit_status.success?
  commit = commit.strip
  tree, tree_stderr, tree_status = Open3.capture3("git", "-C", ROOT, "show", "-s", "--format=%T", commit)
  raise tree_stderr unless tree_status.success?
  tree = tree.strip

  p1 = truth.fetch("strict_phase_gate_ledger").fetch("phases").fetch("P1")
  p1_item_ids = p1.fetch("required_item_ids")
  raise "unexpected P1 required-item cardinality" unless p1_item_ids.length == 8
  fixture_missing_id = p1_item_ids.last
  p1.fetch("required_items")[fixture_missing_id] = {
    "status" => "MISSING",
    "task_history_key" => nil,
    "task_id" => nil,
    "acceptance_commit" => nil,
    "acceptance_tree" => nil,
    "gate_evidence" => {
      "receipt_type" => nil,
      "path" => nil,
      "byte_length" => nil,
      "sha256" => nil
    }
  }
  p1["status"] = "INCOMPLETE"
  p1["derived_completion"] = {"completed" => 7, "total" => 8, "percent" => 87.5}
  p1["founder_phase_gate"] = {
    "status" => "NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS",
    "decision_id" => nil,
    "path" => nil,
    "byte_length" => nil,
    "sha256" => nil
  }
  truth["p1_partial_exit"]["strict_completion"] = {"completed" => 7, "total" => 8, "percent" => 87.5}
  truth["p1_partial_exit"]["missing_exit_items"] = [fixture_missing_id]
  truth["p1_partial_exit"]["phase_pass_claimed"] = false
  truth["p1_partial_exit"]["completion_100_percent_claimed"] = false
  truth["project"]["p1_execution_status"] = "STOPPED_AT_FOUNDER_PHASE_GATE"

  seven_of_eight_path = File.join(audit, "strict-p1-seven-of-eight.yaml")
  File.binwrite(seven_of_eight_path, YAML.dump(truth))
  stdout, stderr, status = run_phase_fixture(
    seven_of_eight_path, "P1", "NONE", "ROUTE_ACTIVATION"
  )
  raise "strict P1 7/8 fixture failed\n#{stdout}#{stderr}" unless status.success?

  missing_ids = p1.fetch("required_items").select { |_id, item| item["status"] == "MISSING" }.keys
  raise "controlled P1 missing Gate fixture drift" unless missing_ids == [fixture_missing_id]

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

  p1["status"] = "EXIT_GATE_READY"
  p1["derived_completion"] = {"completed" => 8, "total" => 8, "percent" => 100}
  p1["founder_phase_gate"] = {
    "status" => "ELIGIBLE_AWAITING_FOUNDER_DECISION",
    "decision_id" => nil,
    "path" => nil,
    "byte_length" => nil,
    "sha256" => nil
  }
  truth["p1_partial_exit"]["strict_completion"] = {"completed" => 8, "total" => 8, "percent" => 100}
  truth["p1_partial_exit"]["missing_exit_items"] = []
  truth["p1_partial_exit"]["phase_pass_claimed"] = false
  truth["p1_partial_exit"]["completion_100_percent_claimed"] = true
  truth["project"]["p1_execution_status"] = "STOPPED_AT_FOUNDER_PHASE_GATE"

  exit_ready_path = File.join(audit, "strict-p1-exit-gate-ready.yaml")
  File.binwrite(exit_ready_path, YAML.dump(truth))
  stdout, stderr, status = run_phase_fixture(exit_ready_path, "P1", "NONE", "ROUTE_ACTIVATION")
  raise "strict P1 Exit-Gate-ready fixture failed\n#{stdout}#{stderr}" unless status.success?
  _stdout, _stderr, premature_p2_status = run_phase_fixture(
    exit_ready_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "P2 was admitted before Founder P1 Phase Gate PASS" if premature_p2_status.success?

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

  missing_gate_truth = Marshal.load(Marshal.dump(truth))
  missing_gate_truth.dig("strict_phase_gate_ledger", "phases", "P1", "founder_phase_gate").delete("sha256")
  missing_gate_path = File.join(audit, "strict-p1-founder-gate-missing.yaml")
  File.binwrite(missing_gate_path, YAML.dump(missing_gate_truth))
  _stdout, _stderr, missing_gate_status = run_phase_fixture(
    missing_gate_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "missing Founder Gate field was accepted" if missing_gate_status.success?

  forged_gate_truth = Marshal.load(Marshal.dump(truth))
  forged_gate_truth.dig("strict_phase_gate_ledger", "phases", "P1", "founder_phase_gate")["decision_id"] =
    "P1-FORGED-FOUNDER-GATE"
  forged_gate_path = File.join(audit, "strict-p1-founder-gate-forged.yaml")
  File.binwrite(forged_gate_path, YAML.dump(forged_gate_truth))
  _stdout, _stderr, forged_gate_status = run_phase_fixture(
    forged_gate_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "forged Founder Gate identity was accepted" if forged_gate_status.success?

  drifted_gate_truth = Marshal.load(Marshal.dump(truth))
  drifted_gate_truth.dig("strict_phase_gate_ledger", "phases", "P1", "founder_phase_gate")["sha256"] = "0" * 64
  drifted_gate_path = File.join(audit, "strict-p1-founder-gate-drifted.yaml")
  File.binwrite(drifted_gate_path, YAML.dump(drifted_gate_truth))
  _stdout, _stderr, drifted_gate_status = run_phase_fixture(
    drifted_gate_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "drifted Founder Gate identity was accepted" if drifted_gate_status.success?

  duplicate_gate_path = File.join(audit, "strict-p1-founder-gate-duplicate.yaml")
  duplicate_gate_yaml = YAML.dump(truth).sub(
    /^(\s+)founder_phase_gate:\n/,
    "\\0\\1  status: PASS\n"
  )
  File.binwrite(duplicate_gate_path, duplicate_gate_yaml)
  _stdout, _stderr, duplicate_gate_status = run_phase_fixture(
    duplicate_gate_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "duplicate Founder Gate field was accepted" if duplicate_gate_status.success?

  truth["strict_phase_gate_ledger"]["phases"]["P1"]["required_items"]
    .fetch("REPRODUCIBLE_BASELINE_REPORT")
    .fetch("gate_evidence")["sha256"] = "0" * 64
  tampered_path = File.join(audit, "strict-p1-tampered.yaml")
  File.binwrite(tampered_path, YAML.dump(truth))
  _stdout, _stderr, tampered_status = run_phase_fixture(
    tampered_path, "P2", "NONE", "ROUTE_ACTIVATION"
  )
  raise "tampered Gate identity was accepted" if tampered_status.success?

  puts "STRICT_PHASE_GATE_TESTS: PASS p1_7_of_8=1 exit_gate_ready=1 premature_p2_rejected=1 p1_complete_to_p2_precheck=1 founder_gate_negatives=4 gate_tamper_rejected=1"
ensure
  FileUtils.remove_entry_secure(audit) if File.exist?(audit)
  FileUtils.remove_entry_secure(reviews) if File.exist?(reviews)
  FileUtils.remove_entry_secure(attachment) if File.exist?(attachment)
end

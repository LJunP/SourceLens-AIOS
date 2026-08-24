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
    "envelope stage activated without Task" => lambda do |candidate|
      candidate.dig("phase_execution_envelope", "ordered_stages", 0)["status"] = "ACTIVE"
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

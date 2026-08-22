#!/usr/bin/env ruby
# frozen_string_literal: true

require "json"
require "fileutils"
require "open3"
require "pathname"
require "yaml"
require_relative "validate-p3-final-transactional-route"

root = Pathname.new(__dir__).join("..").realpath
truth_path = root.join("docs/aios/truth/project_state.yaml")
host_authorized_truth = YAML.safe_load(
  truth_path.binread,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)

assertions = 0

def deep_copy(value)
  JSON.parse(JSON.generate(value))
end

def expect_non_pass(root, truth, label)
  candidate = deep_copy(truth)
  before = JSON.generate(candidate)
  yield candidate
  raise "#{label} mutation was a no-op" if JSON.generate(candidate) == before
  P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: candidate)
  raise "#{label} false-PASSed"
rescue P3FinalTransactionalRouteValidationError,
       P3TaskWideReservationRouteValidationError
  true
end

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3TaskWideReservationRouteValidation::ROUTE_SCHEMA
  state = P3TaskWideReservationRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  lifecycle = host_authorized_truth.dig("current_phase_route", "lifecycle_stage")
  expected_state = P3TaskWideReservationRouteValidation::LIFECYCLE_STATES[lifecycle]
  raise "P3 TWRF state drift" unless expected_state && state == expected_state
  assertions += 1

  mutations = {
    "TWRF Route cannot gain an unknown member" => lambda do |candidate|
      candidate["current_phase_route"]["unexpected"] = true
    end,
    "TWRF Founder decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "TWRF canonical ADR identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["canonical_adr"]["sha256"] = "0" * 64
    end,
    "TWRF source authorization body cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["source_body"]["sha256"] = "0" * 64
    end,
    "TWRF canonical start cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["canonical_start"]["tree"] = "0" * 40
    end,
    "TWRF Constitution identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["constitution"]["sha256"] = "0" * 64
    end,
    "TWRF Objective cannot become generic runtime" => lambda do |candidate|
      candidate["current_phase_route"]["objective_id"] = "GENERIC_AGENT_RUNTIME"
    end,
    "TWRF Gate cannot drop task-wide reservation" => lambda do |candidate|
      candidate["current_phase_route"]["strict_exit_gate"]["required_item_ids"].shift
    end,
    "TWRF Gate id cannot regress to workflow-scoped" => lambda do |candidate|
      candidate["current_phase_route"]["strict_exit_gate"]["gate_id"] =
        "TRUSTED_HOST_TCB_DURABLE_TRANSACTIONAL_EXECUTION_WITH_PROCESS_REAL_CONTAINMENT"
    end,
    "TWRF cannot prebind one workflow at task creation" => lambda do |candidate|
      candidate["current_phase_route"]["p3_001_semantics"][
        "prebinding_one_workflow_at_task_creation_allowed"
      ] = true
    end,
    "TWRF stage order cannot reverse" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "TWRF Foundation cannot gain a repair" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][0]["budget"]["same_task_repairs"] = 1
    end,
    "TWRF Product cannot unlock before Foundation" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
    end,
    "TWRF Audit cannot unlock before Product" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][2]["status"] = "ELIGIBLE_NOT_ACTIVATED"
    end,
    "TWRF cumulative consumed accounting cannot reset" => lambda do |candidate|
      candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 0
    end,
    "TWRF cumulative ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_hours"] = 449
    end,
    "TWRF strategic installation cannot claim delivery" => lambda do |candidate|
      candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 75
    end,
    "TWRF governance cannot claim progress" => lambda do |candidate|
      candidate["phase_execution_envelope"]["governance_progress_credit"] = 1
    end,
    "TWRF Founder interruption cannot be fabricated" => lambda do |candidate|
      candidate["founder_escalation_control"]["founder_decision_required"] = true
    end,
    "TWRF next action owner cannot move to Founder" => lambda do |candidate|
      candidate["founder_escalation_control"]["next_action_owner"] = "HUMAN_FOUNDER"
    end,
    "TWRF Task selection cannot move to Founder" => lambda do |candidate|
      candidate["phase_delegation"]["task_selection_owner"] = "HUMAN_FOUNDER"
    end,
    "TWRF Foundation 2 cannot reappear" => lambda do |candidate|
      candidate["phase_delegation"]["anti_loop"]["foundation_2_allowed"] = true
    end,
    "TWRF Candidate 3 cannot reappear" => lambda do |candidate|
      candidate["phase_delegation"]["anti_loop"]["candidate_3_allowed"] = true
    end,
    "TWRF Task scope cannot become open" => lambda do |candidate|
      candidate["phase_boundary"]["task_creation_scope"] = "ANY_P3_TASK"
    end,
    "TWRF active Task cannot appear before activation" => lambda do |candidate|
      candidate["active_work"]["current_task"] =
        P3TaskWideReservationRouteValidation::TASK_IDS.first
    end,
    "TWRF strict Gate item cannot false-accept" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                    "required_items", "TASK_WIDE_PRE_EFFECT_RESERVATION_FRONTIER")["status"] =
        "ACCEPTED"
    end,
    "TWRF compatibility Gate cannot false-accept" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                    "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
    end,
    "TWRF predecessor terminal Route cannot be rewritten" => lambda do |candidate|
      candidate["historical_p3_thtcb_route_terminal"]["status"] = "ACCEPTED"
    end,
    "TWRF rejected lineage cannot become reusable" => lambda do |candidate|
      candidate["current_phase_route"]["rejected_lineage_policy"] = "REUSE_ALLOWED"
    end,
    "TWRF network cannot self-enable" => lambda do |candidate|
      candidate["current_phase_route"]["external_effect_authority"]["network"] = true
    end,
    "TWRF Docker registry cannot self-enable" => lambda do |candidate|
      candidate["current_phase_route"]["external_effect_authority"]["docker_registry"] = true
    end,
    "TWRF cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "TWRF cannot close the Long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end
  }
  mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end
  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=#{lifecycle}"
  exit 0
end

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3FinalTransactionalRouteValidation::THTCB_ROUTE_SCHEMA
  state = P3FinalTransactionalRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  lifecycle = host_authorized_truth.dig("current_phase_route", "lifecycle_stage")
  expected_state = P3FinalTransactionalRouteValidation::THTCB_LIFECYCLE_STATES[lifecycle]
  raise "P3 THTCB state drift" unless expected_state && state == expected_state
  assertions += 1

  mutations = {
    "THTCB Route cannot gain an unknown member" => lambda do |candidate|
      candidate["current_phase_route"]["unexpected"] = true
    end,
    "THTCB Founder decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "THTCB authorization body identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["source_body"]["sha256"] =
        "0" * 64
    end,
    "THTCB canonical start cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["canonical_start"]["tree"] = "0" * 40
    end,
    "THTCB Constitution identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["constitution"]["sha256"] = "0" * 64
    end,
    "THTCB Objective cannot become generic runtime" => lambda do |candidate|
      candidate["current_phase_route"]["objective_id"] = "GENERIC_AGENT_RUNTIME"
    end,
    "THTCB trusted computing base cannot shrink" => lambda do |candidate|
      candidate["current_phase_route"]["threat_model"]["trusted_computing_base"].pop
    end,
    "THTCB included threat set cannot shrink" => lambda do |candidate|
      candidate["current_phase_route"]["threat_model"]["included_threats"].pop
    end,
    "THTCB excluded compromise cannot become a defended claim" => lambda do |candidate|
      candidate["current_phase_route"]["threat_model"]["excluded_as_tcb_compromise"].delete(
        "SAME_USER_PROCESS_WITH_TCB_WRITE_AUTHORITY"
      )
    end,
    "THTCB strict Exit Gate id cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["strict_exit_gate"]["gate_id"] = "STRONG_HOST_ISOLATION"
    end,
    "THTCB Product and Audit order cannot reverse" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "THTCB Foundation Task cannot reappear" => lambda do |candidate|
      candidate["current_phase_route"]["anti_loop"]["foundation_task_allowed"] = true
    end,
    "THTCB Product budget cannot expand" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][0]["budget"]["engineering_hours"] = 49
    end,
    "THTCB Audit cannot unlock before Product acceptance" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] =
        "ELIGIBLE_MASTER_ACTIVATE_IMMEDIATELY"
    end,
    "THTCB Audit cannot gain rerun-to-pass" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["budget"]["rerun_to_pass_allowed"] =
        true
    end,
    "THTCB cumulative consumed accounting cannot reset" => lambda do |candidate|
      candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 0
    end,
    "THTCB cumulative ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_hours"] = 385
    end,
    "THTCB strategic installation cannot claim progress" => lambda do |candidate|
      candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 75
    end,
    "THTCB governance cannot claim progress" => lambda do |candidate|
      candidate["phase_execution_envelope"]["governance_progress_credit"] = 1
    end,
    "THTCB one-shot JRE acquisition cannot become open network" => lambda do |candidate|
      candidate["phase_execution_envelope"]["external_effects"]["network"] = true
    end,
    "THTCB Founder interruption cannot be fabricated" => lambda do |candidate|
      candidate["founder_escalation_control"]["founder_decision_required"] =
        !candidate["founder_escalation_control"]["founder_decision_required"]
    end,
    "THTCB next action owner cannot move to Founder" => lambda do |candidate|
      candidate["founder_escalation_control"]["next_action_owner"] = "FORGED_OWNER"
    end,
    "THTCB delegated Task selection cannot move to Founder" => lambda do |candidate|
      candidate["phase_delegation"]["task_selection_owner"] = "HUMAN_FOUNDER"
    end,
    "THTCB second repair cannot reappear" => lambda do |candidate|
      candidate["phase_delegation"]["anti_loop"]["second_same_task_repair_allowed"] = true
    end,
    "THTCB Task scope cannot become open" => lambda do |candidate|
      candidate["phase_boundary"]["task_creation_scope"] = "ANY_P3_TASK"
    end,
    "THTCB Worker root cannot escape" => lambda do |candidate|
      candidate["phase_boundary"]["role_write_roots"]["worker"] = ["/"]
    end,
    "THTCB Provider cannot self-enable" => lambda do |candidate|
      candidate["phase_boundary"]["default_external_effects"]["provider"] = true
    end,
    "THTCB active Product identity cannot drift" => lambda do |candidate|
      candidate["active_work"]["current_task"] = "FORGED_TASK"
    end,
    "THTCB active Product authority cannot drift" => lambda do |candidate|
      if candidate["active_work"]["authority_record"]
        candidate["active_work"]["authority_record"]["sha256"] = "0" * 64
      else
        candidate["active_work"]["last_completed_task"]["terminal_receipt"]["sha256"] =
          "0" * 64
      end
    end,
    "THTCB locked Audit budget cannot expand" => lambda do |candidate|
      candidate["active_work"]["next_stage_budget"]["calendar_days"] = 7
    end,
    "THTCB Product activation cannot claim engineering progress" => lambda do |candidate|
      candidate["phase_execution_claim"]["real_engineering_progress"] = 1
    end,
    "THTCB Product cannot be marked changed before implementation" => lambda do |candidate|
      candidate["phase_execution_claim"]["product_capability_changed"] = true
    end,
    "THTCB candidate cannot integrate before independent acceptance" => lambda do |candidate|
      candidate["phase_execution_claim"]["candidate_integration_allowed"] = true
    end,
    "THTCB claim Route cannot drift" => lambda do |candidate|
      candidate["claim_boundary"]["current_phase_route"] = "FORGED_ROUTE"
    end,
    "THTCB strict Gate item cannot false-accept" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "current_exit_gate",
                    "required_items", "AUTHORIZATION_AND_INTENT_DURABILITY")["status"] =
        "ACCEPTED"
    end,
    "THTCB compatibility Gate cannot false-accept" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                    "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
    end,
    "THTCB historical terminal Route cannot be rewritten" => lambda do |candidate|
      candidate["historical_p3_txc_control_recovery_route_terminal"]["status"] = "ACCEPTED"
    end,
    "THTCB rejected lineage cannot become reusable" => lambda do |candidate|
      candidate["current_phase_route"]["rejected_lineage_policy"] = "REUSE_ALLOWED"
    end,
    "THTCB Docker registry cannot self-enable" => lambda do |candidate|
      candidate["current_phase_route"]["external_effect_authority"]["docker_registry"] = true
    end,
    "THTCB cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "THTCB cannot close the Long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end,
    "THTCB current decision cannot be detached from Goal" => lambda do |candidate|
      candidate["goal"]["current_strategic_decision"]["decision_id"] = "FORGED"
    end
  }
  mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end
  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=#{lifecycle}"
  exit 0
end

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3FinalTransactionalRouteValidation::TXC_ROUTE_SCHEMA
  state = P3FinalTransactionalRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  expected_state = P3FinalTransactionalRouteValidation::TXC_LIFECYCLE_STATES.fetch(
    host_authorized_truth.dig("current_phase_route", "lifecycle_stage")
  )
  raise "P3 TXC current route state drift" unless state == expected_state
  assertions += 1

  mutations = {
    "TXC unknown route member cannot enter the closed state machine" => lambda do |candidate|
      candidate["current_phase_route"]["unexpected_route_member"] = true
    end,
    "TXC decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "TXC lifecycle cannot become an undeclared successor" => lambda do |candidate|
      candidate["current_phase_route"]["lifecycle_stage"] = "SUCCESSOR_READY"
    end,
    "TXC objective cannot become a generic runtime" => lambda do |candidate|
      candidate["current_phase_route"]["objective_id"] = "GENERIC_AGENT_RUNTIME"
    end,
    "TXC stage order cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "TXC Product budget cannot expand" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][0]["budget"]["engineering_hours"] = 49
    end,
    "TXC Audit cannot unlock before Product acceptance" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "TXC cumulative accounting cannot reset" => lambda do |candidate|
      candidate["current_phase_route"]["cumulative_accounting"]["consumed"]["engineering_tasks"] = 0
    end,
    "TXC cumulative ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_tasks"] = 13
    end,
    "TXC Stage0 cannot claim delivery progress" => lambda do |candidate|
      candidate["current_phase_route"]["progression"]["delivery_percent"] = 75
    end,
    "TXC strict Gate item cannot false-accept" => lambda do |candidate|
      item = candidate.dig("strict_phase_gate_ledger", "phases", "P3",
                           "current_exit_gate", "required_items",
                           "AUTHORIZATION_AND_INTENT_DURABILITY")
      item["status"] = "ACCEPTED"
    end,
    "TXC compatibility Gate cannot false-accept" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                    "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
    end,
    "TXC Founder decision bit cannot drift across lifecycle states" => lambda do |candidate|
      current = candidate["founder_escalation_control"]["founder_decision_required"]
      candidate["founder_escalation_control"]["founder_decision_required"] = !current
    end,
    "TXC delegated owner cannot move to Founder" => lambda do |candidate|
      candidate["phase_delegation"]["task_selection_owner"] = "HUMAN_FOUNDER"
    end,
    "TXC Task scope cannot become open" => lambda do |candidate|
      candidate["phase_boundary"]["task_creation_scope"] = "ANY_P3_TASK"
    end,
    "TXC Task kind cannot become open" => lambda do |candidate|
      candidate["phase_boundary"]["allowed_task_kinds"] << "ARBITRARY_TASK"
    end,
    "TXC capability cannot become open" => lambda do |candidate|
      candidate["phase_boundary"]["allowed_capabilities"] << "OPEN_AGENT_SHELL"
    end,
    "TXC Worker root cannot escape" => lambda do |candidate|
      candidate["phase_boundary"]["role_write_roots"]["worker"] = ["/"]
    end,
    "TXC Phase boundary network cannot self-enable" => lambda do |candidate|
      candidate["phase_boundary"]["default_external_effects"]["network"] = true
    end,
    "TXC Phase boundary activation lock cannot disappear" => lambda do |candidate|
      candidate["phase_boundary"]["task_creation_lock_after_activation"] = false
    end,
    "TXC deferred Provider capability cannot disappear" => lambda do |candidate|
      candidate["phase_boundary"]["deferred_capabilities"].delete("PROVIDER")
    end,
    "TXC Phase boundary cannot fabricate a Founder action" => lambda do |candidate|
      candidate["phase_boundary"]["user_action_required"] = "FOUNDER_APPROVAL"
    end,
    "TXC envelope network cannot self-enable" => lambda do |candidate|
      candidate["phase_execution_envelope"]["external_effects"]["network"] = true
    end,
    "TXC envelope milestone cannot false-accept" => lambda do |candidate|
      candidate["phase_execution_envelope"]["accepted_milestones"] <<
        "TRANSACTIONAL_INVOCATION_COORDINATOR_PRODUCT"
    end,
    "TXC envelope cannot false-complete" => lambda do |candidate|
      candidate["phase_execution_envelope"]["status"] = "COMPLETE"
    end,
    "TXC active-work network authority cannot drift" => lambda do |candidate|
      current = candidate["active_work"]["external_effects"]["network"]
      candidate["active_work"]["external_effects"]["network"] = !current
    end,
    "TXC active-work next budget cannot expand" => lambda do |candidate|
      candidate["active_work"]["next_stage_budget"] = {"engineering_hours" => 49}
    end,
    "TXC active-work owner cannot move to Founder" => lambda do |candidate|
      candidate["active_work"]["roles"]["owner"] = "HUMAN_FOUNDER"
    end,
    "TXC active-work allowlist cannot escape" => lambda do |candidate|
      candidate["active_work"]["allowlisted_paths"] << "/"
    end,
    "TXC inactive work cannot gain a custody root" => lambda do |candidate|
      candidate["active_work"]["dependency_custody_root"] = "/private/tmp/forged"
    end,
    "TXC delegated decision set cannot become open" => lambda do |candidate|
      candidate["phase_delegation"]["agent_delegated_decisions"] << "OPEN_ENDED_RUNTIME"
    end,
    "TXC Stage0 cannot claim engineering progress" => lambda do |candidate|
      candidate["phase_execution_claim"]["real_engineering_progress"] = 1
    end,
    "TXC Stage0 cannot claim a product change" => lambda do |candidate|
      candidate["phase_execution_claim"]["product_capability_changed"] = true
    end,
    "TXC project cannot false-complete P3" => lambda do |candidate|
      candidate["project"]["p3_execution_status"] = "COMPLETE"
    end,
    "TXC rejected lineage cannot become reusable" => lambda do |candidate|
      candidate["current_phase_route"]["rejected_lineage_policy"] = "REUSE_ALLOWED"
    end,
    "TXC Phase-entry reference cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["phase_entry_route_ref"] = "FORGED"
    end,
    "TXC historical terminal identity set cannot expand" => lambda do |candidate|
      candidate["current_phase_route"]["historical_terminal_identities"]["extra"] =
        candidate["current_phase_route"]["historical_terminal_identities"]["hpe_terminal_receipt"]
    end,
    "TXC Product-eligible state cannot retain Task authority" => lambda do |candidate|
      candidate["active_work"]["authority_record"] = {
        "path" => "/private/tmp/forbidden", "byte_length" => 1, "sha256" => "0" * 64
      }
    end,
    "TXC current network effect cannot self-enable" => lambda do |candidate|
      candidate["current_phase_route"]["current_external_effects"]["network"] = true
    end,
    "TXC cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "TXC cannot close the Long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end
  }
  mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end

  natural_language_variants = [
    lambda do |candidate|
      candidate["goal"]["current_state_note"] =
        "同义改写：P3 仍为 25% delivery，strict Exit 仍为 0%。"
    end,
    lambda do |candidate|
      candidate["goal"]["current_state_note"] =
        candidate["goal"]["current_state_note"].gsub(" ", "  ")
    end,
    lambda do |candidate|
      candidate["project"]["positioning"] =
        "Trustworthy autonomous agent infrastructure research platform; software engineering first!"
    end
  ]
  natural_language_variants.each_with_index do |mutation, index|
    candidate = deep_copy(host_authorized_truth)
    before = JSON.generate(candidate)
    mutation.call(candidate)
    raise "TXC natural-language mutation #{index + 1} was a no-op" if JSON.generate(candidate) == before
    variant_state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: candidate)
    raise "TXC natural-language variation changed structured disposition" unless
      variant_state == expected_state
    assertions += 1
  end

  if ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"].to_s.empty? &&
     host_authorized_truth.dig("current_phase_route", "lifecycle_stage") !=
       "PRODUCT_STAGE_ELIGIBLE"
    puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions " \
         "mode=CURRENT_TXC_LIFECYCLE_NO_STAGE0_MANIFEST_REPLAY"
    exit 0
  end

  decision, = P3FinalTransactionalRouteValidation.validate_txc_decision!
  manifest_context = if ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"].to_s.empty?
    P3FinalTransactionalRouteValidation.txc_installed_context!(
      root: root, truth: host_authorized_truth
    )
  else
    P3FinalTransactionalRouteValidation.atomic_staging_context!(
      root: root, truth: host_authorized_truth
    )
  end
  raise "TXC dual-mode manifest context was not resolved" unless manifest_context
  manifest = manifest_context.fetch("manifest")
  manifest_staging_root = Pathname.new(manifest_context.fetch("staging_root")).realpath
  canonical_mode = manifest_context["mode"] == "CANONICAL_INSTALLED_REPLAY_MODE" ?
    :installed : :staging
  {
    "wrong candidate parent" => lambda do |candidate|
      candidate["candidate"]["parent_commit"] = "0" * 40
    end,
    "wrong canonical baseline" => lambda do |candidate|
      candidate["baseline"]["tree"] = "f" * 40
    end,
    "wrong recorded staging root" => lambda do |candidate|
      candidate["recorded_staging_root"] = "/private/tmp/forged-p3-txc-stage"
    end
  }.each do |label, mutation|
    candidate = deep_copy(manifest)
    mutation.call(candidate)
    begin
      P3FinalTransactionalRouteValidation.txc_validate_atomic_manifest_values!(
        candidate, root: manifest_staging_root, decision: decision,
        canonical_mode: canonical_mode
      )
      raise "TXC staging manifest #{label} false-PASSed"
    rescue P3FinalTransactionalRouteValidationError
      assertions += 1
    end
  end

  begin
    forged_dir = Dir.mktmpdir("p3-txc-forged-manifest-")
    forged_path = File.join(forged_dir, "P3_TXC_ATOMIC_STAGING_MANIFEST_GENERATION_1_V1.json")
    File.binwrite(forged_path, JSON.generate(manifest))
    File.chmod(0o444, forged_path)
    previous = ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"]
    ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"] = forged_path
    begin
      if previous.to_s.empty?
        P3FinalTransactionalRouteValidation.txc_installed_context!(
          root: root, truth: host_authorized_truth
        )
      else
        P3FinalTransactionalRouteValidation.atomic_staging_context!(
          root: root, truth: host_authorized_truth
        )
      end
      raise "TXC forged staging manifest path false-PASSed"
    rescue P3FinalTransactionalRouteValidationError
      assertions += 1
    ensure
      ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"] = previous
    end
  ensure
    File.chmod(0o644, forged_path) if defined?(forged_path) && File.exist?(forged_path)
    File.delete(forged_path) if defined?(forged_path) && File.exist?(forged_path)
    Dir.rmdir(forged_dir) if defined?(forged_dir) && Dir.exist?(forged_dir)
  end

  begin
    if ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"].to_s.empty?
      P3FinalTransactionalRouteValidation.txc_installed_context!(
        root: root.parent, truth: host_authorized_truth
      )
    else
      P3FinalTransactionalRouteValidation.atomic_staging_context!(
        root: root.parent, truth: host_authorized_truth
      )
    end
    raise "TXC wrong validator root false-PASSed"
  rescue P3FinalTransactionalRouteValidationError
    assertions += 1
  end

  dirty_probe = root.join(".p3-txc-dirty-head-negative-probe")
  begin
    File.binwrite(dirty_probe, "DIRTY_HEAD_NEGATIVE_PROBE\n")
    if ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"].to_s.empty?
      P3FinalTransactionalRouteValidation.txc_installed_context!(
        root: root, truth: host_authorized_truth
      )
    else
      P3FinalTransactionalRouteValidation.atomic_staging_context!(
        root: root, truth: host_authorized_truth
      )
    end
    raise "TXC dirty staging HEAD false-PASSed"
  rescue P3FinalTransactionalRouteValidationError
    assertions += 1
  ensure
    dirty_probe.delete if dirty_probe.exist?
  end
  raise "TXC negative probes left the staging repository dirty" unless
    Open3.capture3("git", "status", "--porcelain=v1", "--untracked-files=all",
                   chdir: root.to_s).first.empty?

  drift_root = Dir.mktmpdir("p3-txcr-canonical-drift-")
  begin
    drift_repo = File.join(drift_root, "repo")
    _clone_out, clone_err, clone_status = Open3.capture3(
      "git", "clone", "--local", "--no-hardlinks", "--no-checkout",
      decision.dig("canonical_start", "repository"), drift_repo
    )
    raise "TXC canonical-drift clone failed: #{clone_err.strip}" unless clone_status.success?
    Open3.capture3("git", "remote", "remove", "origin", chdir: drift_repo)
    _checkout_out, checkout_err, checkout_status = Open3.capture3(
      "git", "checkout", "--detach", decision.dig("canonical_start", "commit"),
      chdir: drift_repo
    )
    raise "TXC canonical-drift checkout failed: #{checkout_err.strip}" unless
      checkout_status.success?
    _branch_out, branch_err, branch_status = Open3.capture3(
      "git", "branch", "-f", "main", decision.dig("canonical_start", "commit"),
      chdir: drift_repo
    )
    raise "TXC canonical-drift branch failed: #{branch_err.strip}" unless branch_status.success?
    _switch_out, switch_err, switch_status = Open3.capture3(
      "git", "switch", "main", chdir: drift_repo
    )
    raise "TXC canonical-drift switch failed: #{switch_err.strip}" unless switch_status.success?
    drift_decision = deep_copy(decision)
    drift_manifest = deep_copy(manifest)
    drift_decision["canonical_start"]["repository"] = File.realpath(drift_repo)
    drift_manifest["canonical_repository"] = File.realpath(drift_repo)
    begin
      P3FinalTransactionalRouteValidation.txc_validate_atomic_manifest_values!(
        drift_manifest, root: manifest_staging_root, decision: drift_decision,
        canonical_mode: :installed
      )
      raise "TXC canonical drift false-PASSed"
    rescue P3FinalTransactionalRouteValidationError
      assertions += 1
    end
  ensure
    FileUtils.remove_entry(drift_root) if Dir.exist?(drift_root)
  end

  mode = ENV["SOURCELENS_ATOMIC_STAGING_MANIFEST"].to_s.empty? ?
    "CANONICAL_INSTALLED_REPLAY_MODE" : "ATOMIC_STAGING_FIXTURE_MODE"
  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=#{mode}"
  exit 0
end

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3FinalTransactionalRouteValidation::HPE_ROUTE_SCHEMA
  state = P3FinalTransactionalRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  expected_state = P3FinalTransactionalRouteValidation::HPE_LIFECYCLE_STATES.fetch(
    host_authorized_truth.dig("current_phase_route", "lifecycle_stage")
  )
  raise "P3 HPE current route state drift" unless state == expected_state
  assertions += 1

  decision = JSON.parse(File.binread(P3FinalTransactionalRouteValidation::HPE_DECISION.fetch("path")))
  expected_resource_keys = %w[
    branch worktree evidence_root contract_path authority_path candidate_manifest_path
    gate_evidence_path cycle_1_finding_set_path task_gate_pass_receipt_path
    task_gate_non_pass_receipt_path cycle_1_candidate_manifest_path
    cycle_1_gate_evidence_path cycle_1_cto_review_path cycle_1_security_review_path
    cycle_1_quality_review_path cto_review_path security_review_path quality_review_path
    rejected_bundle_path bundle_attestation_path
  ]
  raise "P3 HPE frozen resource schema drift" unless
    decision.dig("route", "stages").all? do |stage|
      stage.fetch("resources").keys.sort == expected_resource_keys.sort
    end
  assertions += 1

  validator_source = root.join("scripts/validate-p3-final-transactional-route.rb").binread
  receipt_source = validator_source[/^  def validate_hpe_stage_receipt!.*?(?=^  def )/m]
  attestation_source = validator_source[/^  def validate_hpe_terminal_attestation!.*?(?=^  def )/m]
  raise "P3 HPE terminal current-state rejected-lineage replay regression" unless
    receipt_source && attestation_source &&
    !receipt_source.include?("validate_hpe_terminal_bundle!") &&
    !attestation_source.include?("validate_hpe_terminal_bundle!") &&
    !receipt_source.include?('"git", "bundle"') &&
    !attestation_source.include?('"git", "bundle"') &&
    receipt_source.include?("bundle_verification_attestation") &&
    attestation_source.include?('"future_current_state_lineage_replay_allowed"] == false')
  assertions += 1

  candidate_source = validator_source[/^  def validate_hpe_candidate_manifest!.*?(?=^  def )/m]
  gate_source = validator_source[/^  def validate_hpe_gate_evidence!.*?(?=^  def )/m]
  review_source = validator_source[/^  def validate_hpe_review!.*?(?=^  def )/m]
  gate_partition_source = validator_source[/^  def hpe_executable_gate_requirements.*?(?=^  def )/m]
  pointer_source = validator_source[/^  def hpe_json_pointer.*?(?=^  def )/m]
  raise "P3 HPE frozen candidate/Gate/review safety semantics drift" unless
    candidate_source && candidate_source.include?("--diff-filter=ACMRD") &&
    candidate_source.include?("%w[A M].include?(status)") &&
    candidate_source.include?("%w[100644 100755]") &&
    gate_source && gate_source.include?("parse_tik_json!") &&
    gate_source.include?("source_identities") && gate_source.include?("derivation") &&
    gate_source.include?("actual_values == pass_values") &&
    gate_partition_source &&
    gate_partition_source.include?('gates - ["THREE_INDEPENDENT_REVIEWS_PASS"]') &&
    pointer_source && pointer_source.include?("JSON pointer") && review_source &&
    review_source.include?("regression_ids & frozen_ids") &&
    review_source.include?("closed + unresolved")
  assertions += 1

  creator_source = validator_source[/^  def create_hpe_terminal_bundle_attestation!.*?(?=^  def )/m]
  raise "P3 HPE one-shot terminalization or canonical integration semantics drift" unless
    creator_source && creator_source.include?("tik_reserve_exclusive_create_once_file!") &&
    creator_source.include?("validate_hpe_terminal_bundle!") &&
    creator_source.index("tik_reserve_exclusive_create_once_file!") <
      creator_source.index("validate_hpe_terminal_bundle!") &&
    receipt_source.include?("expected_receipt_gate_results") &&
    receipt_source.include?("activation_parent.fetch(\"commit\")") &&
    receipt_source.include?("expected_integration_paths")
  assertions += 1

  hpe_mutations = {
    "HPE unknown route member cannot enter the closed state machine" => lambda do |candidate|
      candidate["current_phase_route"]["unexpected_route_member"] = true
    end,
    "HPE decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "HPE installed authorization body identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["source_body"]["sha256"] =
        "0" * 64
    end,
    "HPE canonical start cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["canonical_start"]["commit"] = "0" * 40
    end,
    "HPE lifecycle cannot be unknown" => lambda do |candidate|
      candidate["current_phase_route"]["lifecycle_stage"] = "SUCCESSOR_READY"
    end,
    "HPE lifecycle execution status cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["execution_status"] = "READY_TO_ACTIVATE_PRODUCT"
    end,
    "HPE lifecycle scheduling cannot become a Founder daily gate" => lambda do |candidate|
      candidate["current_phase_route"]["scheduling_status"] =
        "FOUNDER_RESERVED_ROUTE_CHANGE_DECISION_REQUIRED"
    end,
    "HPE stage order cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "HPE Foundation budget cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["ordered_stages"][0]["budget"]["engineering_hours"] = 9
    end,
    "HPE Product cannot unlock before Foundation" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "HPE cumulative Task ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_tasks"] = 13
    end,
    "HPE consumed accounting cannot reset" => lambda do |candidate|
      candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 0
    end,
    "HPE Stage 0 cannot claim delivery progress" => lambda do |candidate|
      candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 50
    end,
    "HPE delegated continuation cannot lose Master owner" => lambda do |candidate|
      candidate["founder_escalation_control"]["next_action_owner"] = "NONE"
    end,
    "HPE ready state cannot retain Task authority" => lambda do |candidate|
      candidate["active_work"]["authority_record"] =
        P3FinalTransactionalRouteValidation::HPE_AUTHORIZATION_BODY
    end,
    "HPE phase boundary cannot authorize repository root" => lambda do |candidate|
      candidate["phase_boundary"]["role_write_roots"]["worker"] = ["/"]
    end,
    "HPE phase boundary cannot enable open shell" => lambda do |candidate|
      candidate["phase_boundary"]["allowed_capabilities"] << "OPEN_AGENT_SHELL"
    end,
    "HPE external network effect cannot be enabled" => lambda do |candidate|
      candidate["current_phase_route"]["external_effects"]["network"] = true
    end,
    "HPE predecessor terminal accounting cannot drift" => lambda do |candidate|
      candidate.dig("active_work", "last_completed_task_identity_accounting",
                    "terminal_receipt")["sha256"] = "0" * 64
    end,
    "HPE strict Exit cannot be claimed during installation" => lambda do |candidate|
      candidate.dig("strict_phase_gate_ledger", "phases", "P3", "required_items",
                    "RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS")["status"] = "ACCEPTED"
    end,
    "HPE cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "HPE cannot close the Long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end
  }
  hpe_mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end
  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=HPE_CURRENT_ONLY_NO_REJECTED_LINEAGE_REPLAY"
  exit 0
end

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3FinalTransactionalRouteValidation::TIK_ROUTE_SCHEMA
  state = P3FinalTransactionalRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  expected_state = P3FinalTransactionalRouteValidation::TIK_LIFECYCLE_STATES.fetch(
    host_authorized_truth.dig("current_phase_route", "lifecycle_stage")
  )
  raise "P3 TIK current route state drift" unless
    state == expected_state
  assertions += 1
  expected_resource_keys = %w[
    branch worktree evidence_root contract_path authority_path candidate_manifest_path
    cycle_1_candidate_manifest_path cycle_1_gate_evidence_path gate_evidence_path
    rejected_bundle_path bundle_attestation_path
    cycle_1_finding_set_path cycle_1_cto_review_path cycle_1_security_review_path
    cycle_1_quality_review_path cto_review_path security_review_path quality_review_path
    task_gate_pass_receipt_path task_gate_non_pass_receipt_path
  ]
  raise "P3 TIK frozen resource schema drift" unless
    P3FinalTransactionalRouteValidation::TIK_STAGE_RESOURCES.all? do |resource|
      resource.keys.sort == expected_resource_keys.sort
    end
  assertions += 1

  validator_source = root.join("scripts/validate-p3-final-transactional-route.rb").binread
  stage_receipt_source = validator_source[/^  def validate_tik_stage_receipt!.*?(?=^  def )/m]
  attestation_source = validator_source[/^  def validate_tik_bundle_attestation!.*?(?=^  def )/m]
  raise "P3 TIK terminal current-state lineage replay regression" unless
    stage_receipt_source &&
    !stage_receipt_source.include?("validate_tik_terminal_bundle!") &&
    stage_receipt_source.include?("bundle_verification_attestation") && attestation_source &&
    !attestation_source.include?("validate_tik_terminal_bundle!")
  assertions += 1

  bundle_verifier_source = validator_source[/^  def validate_tik_terminal_bundle!.*?(?=^  def )/m]
  attestation_creator_source = validator_source[
    /^  def create_tik_terminal_bundle_attestation!.*?(?=^  def )/m
  ]
  reservation_source = validator_source[
    /^  def tik_reserve_exclusive_create_once_file!.*?(?=^  def )/m
  ]
  raise "P3 TIK one-time bundle verifier escaped the active Evidence root" unless
    bundle_verifier_source &&
    bundle_verifier_source.include?("terminal_root.to_s") &&
    bundle_verifier_source.include?(".p3-tik-bundle-verifier-") &&
    reservation_source && reservation_source.include?("File::EXCL") &&
    reservation_source.include?("File::NOFOLLOW") && attestation_creator_source &&
    attestation_creator_source.index("tik_reserve_exclusive_create_once_file!") <
      attestation_creator_source.index("validate_tik_terminal_bundle!")
  assertions += 1

  tree_entry_source = validator_source[/^  def tik_git_tree_entry!.*?(?=^  def )/m]
  route_source = validator_source[/^  def validate_tik_route!.*?(?=^  def )/m]
  raise "P3 TIK Git symlink or Audit ancestor regression" unless
    tree_entry_source && tree_entry_source.include?("%w[100644 100755]") &&
    tree_entry_source.include?('match[2] == "blob"') && route_source &&
    route_source.include?('audit.fetch("candidate").slice("commit", "tree", "source_branch") ==') &&
    route_source.include?('product.fetch("candidate").slice("commit", "tree", "source_branch")')
  assertions += 1

  tik_mutations = {
    "TIK unknown route member cannot enter the closed state machine" => lambda do |candidate|
      candidate["current_phase_route"]["unexpected_route_member"] = true
    end,
    "TIK decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "TIK authorization body identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["source_body"]["sha256"] =
        "0" * 64
    end,
    "TIK activation parent cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["activation_parent"]["commit"] = "0" * 40
    end,
    "TIK Constitution binding cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["constitution"]["version"] = "2.7"
    end,
    "TIK workflow cannot become a dynamic broker" => lambda do |candidate|
      candidate["current_phase_route"]["workflow_id"] = "GENERIC_TOOL_BROKER"
    end,
    "TIK lifecycle cannot be unknown" => lambda do |candidate|
      candidate["current_phase_route"]["lifecycle_stage"] = "SUCCESSOR_READY"
    end,
    "TIK lifecycle execution status cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["execution_status"] = "READY_TO_ACTIVATE_PRODUCT"
    end,
    "TIK lifecycle scheduling status cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["scheduling_status"] = "FOUNDER_WAIT"
    end,
    "TIK stage order cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "TIK stage Task identity cannot become Candidate 3" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][0]["task_id"] =
        "AIOS-P3-TIK-F1-CANDIDATE-3"
    end,
    "TIK stage budget cannot expand" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["budget"]["engineering_hours"] = 49
    end,
    "TIK Product cannot unlock before Foundation" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "TIK Audit cannot unlock before Product" => lambda do |candidate|
      candidate["phase_execution_envelope"]["ordered_stages"][2]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "TIK cumulative Task ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_tasks"] = 12
    end,
    "TIK cumulative hour ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_hours"] = 337
    end,
    "TIK cumulative consumed accounting cannot reset" => lambda do |candidate|
      candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 0
    end,
    "TIK route capacity cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["route_capacity"]["calendar_days"] = 25
    end,
    "TIK Stage 0 cannot claim engineering progress" => lambda do |candidate|
      candidate["phase_execution_envelope"]["governance_progress_credit"] = 1
    end,
    "TIK delegated continuation cannot lose the Master owner" => lambda do |candidate|
      candidate["founder_escalation_control"]["next_action_owner"] = "NONE"
    end,
    "TIK delegated continuation cannot become a routine Founder gate" => lambda do |candidate|
      candidate["founder_escalation_control"]["next_action_owner"] = "HUMAN_FOUNDER"
      candidate["founder_escalation_control"]["founder_decision_required"] = true
    end,
    "TIK exact next action cannot drift" => lambda do |candidate|
      candidate["founder_escalation_control"]["next_eligible_action"] = "NONE_CONTINUE"
    end,
    "TIK ready state cannot retain an old Contract" => lambda do |candidate|
      candidate["active_work"]["current_task_contract"] = {
        "path" => "/tmp/old-contract", "byte_length" => 1, "sha256" => "0" * 64
      }
    end,
    "TIK ready state cannot prebind a Task activation parent" => lambda do |candidate|
      candidate["active_work"]["activation_parent_commit"] =
        P3FinalTransactionalRouteValidation::TIK_ACTIVATION_PARENT.fetch("commit")
    end,
    "TIK ready state cannot preauthorize a write path" => lambda do |candidate|
      candidate["active_work"]["allowlisted_paths"] = ["backend-spring/src/main"]
    end,
    "TIK arbitrary create-once blob cannot unlock a completed stage" => lambda do |candidate|
      candidate["active_work"]["completed_tasks"] = [{
        "task_id" => P3FinalTransactionalRouteValidation::TIK_TASK_IDS.fetch(0),
        "status" => "ACCEPTED_TASK_GATE_PASS",
        "contract" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY,
        "authority" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY,
        "candidate_manifest" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY,
        "gate_evidence" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY,
        "independent_reviews" => {
          "cto" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY,
          "security" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY,
          "quality_evaluation" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY
        },
        "task_gate_receipt" => P3FinalTransactionalRouteValidation::TIK_AUTHORIZATION_BODY
      }]
    end,
    "TIK ready state cannot bind an arbitrary authority file" => lambda do |candidate|
      candidate["active_work"]["authority_record"] = {
        "path" => "/etc/hosts", "byte_length" => 1, "sha256" => "0" * 64
      }
    end,
    "TIK phase boundary cannot authorize the filesystem root" => lambda do |candidate|
      candidate["phase_boundary"]["role_write_roots"]["worker"] = ["/"]
    end,
    "TIK phase boundary cannot enable open shell" => lambda do |candidate|
      candidate["phase_boundary"]["allowed_capabilities"] << "OPEN_AGENT_SHELL"
    end,
    "TIK phase boundary cannot erase a deferred capability" => lambda do |candidate|
      candidate["phase_boundary"]["deferred_capabilities"].delete("OPEN_AGENT_SHELL")
    end,
    "TIK remaining-capacity lock reason cannot be self-reported" => lambda do |candidate|
      candidate["phase_execution_envelope"]["remaining_capacity_lock_reason"] =
        "ROUTE_TERMINAL_EXACT_AUTHORIZATION_PROHIBITS_REUSE_OR_FOLLOW_ON_TASK"
    end,
    "TIK ordinary terminal label cannot synthesize a Founder trigger" => lambda do |candidate|
      candidate["current_phase_route"]["lifecycle_stage"] = "ROUTE_TERMINAL_NON_PASS"
      candidate["current_phase_route"]["terminal_stage_ordinal"] = 1
    end,
    "TIK external effect cannot be enabled" => lambda do |candidate|
      candidate["current_phase_route"]["external_effects"]["network"] = true
    end,
    "TIK rejected lineage cannot become readable" => lambda do |candidate|
      candidate["phase_execution_claim"]["phase_local_frozen_capabilities"].delete(
        "P3_HATB_F1_REJECTED_ENGINEERING_LINEAGE_FROZEN_UNREADABLE"
      )
    end,
    "TIK strict Exit cannot be claimed during installation" => lambda do |candidate|
      required_items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
      required_items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
    end,
    "TIK cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "TIK cannot close the Long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end
  }
  tik_mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end

  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=TIK_CURRENT_ONLY_NO_REJECTED_LINEAGE_REPLAY"
  exit 0
end

if host_authorized_truth.dig("current_phase_route", "schema_version") ==
   P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_ROUTE_SCHEMA
  state = P3FinalTransactionalRouteValidation.validate_truth!(
    root: root, truth: host_authorized_truth
  )
  expected_state =
    if host_authorized_truth.dig("current_phase_route", "lifecycle_stage") ==
       "FOUNDATION_TASK_TERMINAL_NON_PASS"
      P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_FOUNDATION_TERMINAL_STATE
    elsif host_authorized_truth.dig("current_phase_route", "lifecycle_stage") ==
          "FOUNDATION_TASK_ACTIVE"
      P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_FOUNDATION_ACTIVE_STATE
    else
      P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_ROUTE_STATE
    end
  raise "host-authorized current route state drift" unless state == expected_state
  assertions += 1

  host_authorized_mutations = {
    "host-authorized decision identity cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
    end,
    "host-authorized Objective cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["objective_id"] = "GENERIC_TOOL_BROKER"
    end,
    "host-authorized route cannot omit the capacity trigger" => lambda do |candidate|
      candidate["current_phase_route"]["founder_reserved_triggers_resolved"].pop
    end,
    "host-authorized cumulative Task ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_tasks"] = 11
    end,
    "host-authorized cumulative hour ceiling cannot expand" => lambda do |candidate|
      candidate["phase_execution_envelope"]["limits"]["engineering_hours"] = 320
    end,
    "host-authorized consumed accounting cannot reset" => lambda do |candidate|
      candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 0
    end,
    "host-authorized stage order cannot drift" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].reverse!
    end,
    "host-authorized product cannot unlock before foundation acceptance" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"][1]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "host-authorized audit cannot unlock before product acceptance" => lambda do |candidate|
      candidate["phase_execution_envelope"]["ordered_stages"][2]["status"] =
        "ELIGIBLE_NOT_ACTIVATED"
    end,
    "host-authorized installation cannot claim delivery credit" => lambda do |candidate|
      candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 50
    end,
    "host-authorized installation cannot weaken strict Exit" => lambda do |candidate|
      required_items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
      required_items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
    end,
    "host-authorized installation cannot permit rejected-lineage reuse" => lambda do |candidate|
      candidate["phase_execution_claim"]["phase_local_frozen_capabilities"].delete(
        "P3_002_THROUGH_P3_007_REJECTED_LINEAGE_FROZEN_UNREADABLE"
      )
    end,
    "host-authorized installation cannot authorize a second product Task" => lambda do |candidate|
      candidate["current_phase_route"]["ordered_stages"].insert(
        2, deep_copy(candidate["current_phase_route"]["ordered_stages"][1])
      )
    end,
    "host-authorized installation cannot enter P4" => lambda do |candidate|
      candidate["project"]["p4_entry_status"] = "AUTHORIZED"
    end,
    "host-authorized installation cannot close the long-term Goal" => lambda do |candidate|
      candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
    end
  }

  if expected_state ==
     P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_FOUNDATION_ACTIVE_STATE
    host_authorized_mutations.merge!({
      "active foundation Task identity cannot drift" => lambda do |candidate|
        candidate["active_work"]["current_task"] = "AIOS-P3-008_FORBIDDEN"
      end,
      "active foundation Contract identity cannot drift" => lambda do |candidate|
        candidate["active_work"]["current_task_contract"]["sha256"] = "0" * 64
      end,
      "active foundation authority identity cannot drift" => lambda do |candidate|
        candidate["active_work"]["authority_record"]["sha256"] = "0" * 64
      end,
      "active foundation branch cannot drift" => lambda do |candidate|
        candidate["active_work"]["task_branch"] = "codex/p3-008-forbidden"
      end,
      "active foundation reserved budget cannot drift" => lambda do |candidate|
        candidate["phase_execution_envelope"]["reserved"]["engineering_hours"] = 32
      end,
      "active foundation cannot unlock concurrent capacity" => lambda do |candidate|
        candidate["phase_execution_envelope"]["remaining_capacity_usable"] = true
      end,
      "active foundation cannot permit another Task" => lambda do |candidate|
        candidate["phase_boundary"]["task_creation_allowed"] = true
      end,
      "active foundation cannot claim acceptance before review" => lambda do |candidate|
        candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 50
      end
    })
  end

  if expected_state ==
     P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_FOUNDATION_TERMINAL_STATE
    host_authorized_mutations.merge!({
      "terminal foundation receipt identity cannot drift" => lambda do |candidate|
        candidate["current_phase_route"]["terminal_task"]["terminal_receipt"]["sha256"] =
          "0" * 64
      end,
      "terminal foundation cannot resurrect a branch" => lambda do |candidate|
        candidate["active_work"]["task_branch"] = "codex/p3-hatb-f1-resurrected"
      end,
      "terminal foundation cannot unlock product" => lambda do |candidate|
        candidate["current_phase_route"]["ordered_stages"][1]["status"] =
          "ELIGIBLE_NOT_ACTIVATED"
      end,
      "terminal foundation cannot create a third candidate" => lambda do |candidate|
        candidate["active_work"]["budget_consumed"]["candidate_generations"] = 3
      end,
      "terminal foundation cannot request ordinary Founder approval" => lambda do |candidate|
        candidate["founder_escalation_control"]["founder_decision_required"] = true
      end,
      "terminal foundation cannot close the long-term Goal" => lambda do |candidate|
        candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
      end
    })
  end

  host_authorized_mutations.each do |label, mutation|
    expect_non_pass(root, host_authorized_truth, label, &mutation)
    assertions += 1
  end

  puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions mode=HOST_AUTHORIZED_CURRENT_ONLY_NO_REJECTED_LINEAGE_REPLAY"
  exit 0
end

hold_bytes, hold_stderr, hold_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::HOST_AUTHORIZED_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "strategic HOLD Truth unavailable: #{hold_stderr}" unless hold_status.success?
hold_truth = YAML.safe_load(
  hold_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
hold_state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: hold_truth)
raise "strategic HOLD route state drift" unless
  hold_state == P3FinalTransactionalRouteValidation::HOLD_STATE
assertions += 1

terminal_bytes, terminal_stderr, terminal_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::HOLD_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "terminal Route Truth unavailable: #{terminal_stderr}" unless terminal_status.success?
terminal_truth = YAML.safe_load(
  terminal_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
terminal_state = P3FinalTransactionalRouteValidation.validate_truth!(
  root: root,
  truth: terminal_truth
)
raise "terminal route state drift" unless
  terminal_state == P3FinalTransactionalRouteValidation::TERMINAL_STATE
assertions += 1

active_bytes, active_stderr, active_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::PREACTIVATION_COMMIT}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "active Route Truth unavailable: #{active_stderr}" unless active_status.success?
active_truth = YAML.safe_load(
  active_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
active_tree, tree_stderr, tree_status = Open3.capture3(
  "git", "rev-parse", "#{P3FinalTransactionalRouteValidation::PREACTIVATION_COMMIT}^{tree}",
  chdir: root.to_s
)
raise "active route tree unavailable: #{tree_stderr}" unless tree_status.success?
raise "active route tree drift" unless
  active_tree.strip == P3FinalTransactionalRouteValidation::PREACTIVATION_TREE &&
  active_truth.dig("current_phase_route", "lifecycle_stage") == "PRODUCT_TASK_ACTIVE" &&
  active_truth.dig("active_work", "current_task") == P3FinalTransactionalRouteValidation::TASK_ID
assertions += 1

ready_bytes, ready_stderr, ready_status = Open3.capture3(
  "git", "show",
  "#{P3FinalTransactionalRouteValidation::TASK_ACTIVATION_PARENT.fetch('commit')}:docs/aios/truth/project_state.yaml",
  chdir: root.to_s
)
raise "ready Route Truth unavailable: #{ready_stderr}" unless ready_status.success?
truth = YAML.safe_load(
  ready_bytes,
  permitted_classes: [],
  permitted_symbols: [],
  aliases: false
)
ready_state = P3FinalTransactionalRouteValidation.validate_truth!(root: root, truth: truth)
raise "ready route state drift" unless ready_state == P3FinalTransactionalRouteValidation::READY_STATE
assertions += 1

mutations = {
  "historical route drift" => lambda do |candidate|
    candidate["historical_p3_host_owned_fixed_state_workflow_phase_route"]["status"] = "ACTIVE"
  end,
  "route decision identity drift" => lambda do |candidate|
    candidate["current_phase_route"]["founder_route_decision"]["sha256"] = "0" * 64
  end,
  "route objective drift" => lambda do |candidate|
    candidate["current_phase_route"]["objective_id"] = "DYNAMIC_TOOL_BROKER"
  end,
  "slot kind drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][0]["kind"] = "EVALUATION_ONLY"
  end,
  "slot dependency drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][1]["predecessor"] = "NONE"
  end,
  "slot budget drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][0]["budget"]["engineering_hours"] = 33
  end,
  "slot lifecycle drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
  end,
  "prior ledger row drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"][2]["status"] = "ACCEPTED_INTEGRATED"
  end,
  "consumed budget drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 5
  end,
  "remaining budget drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining"]["engineering_hours"] = 96
  end,
  "capacity lock drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining_capacity_usable"] = false
  end,
  "delivery credit drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 75
  end,
  "strict exit drift" => lambda do |candidate|
    items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
    items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
  end,
  "P4 entry drift" => lambda do |candidate|
    candidate["project"]["p4_entry_status"] = "AUTHORIZED"
  end,
  "task creation scope drift" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_scope"] = "ANY_P3_TASK"
  end,
  "reserved trigger drift" => lambda do |candidate|
    candidate["founder_escalation_control"]["reserved_trigger"]["category"] =
      "PHASE_ENTRY_OR_EXIT"
  end,
  "delegation owner drift" => lambda do |candidate|
    candidate["phase_delegation"]["task_selection_owner"] = "FOUNDER"
  end,
  "active-work decision drift" => lambda do |candidate|
    candidate["active_work"]["founder_reserved_authorization_sha256"] = "f" * 64
  end,
  "active-work task drift" => lambda do |candidate|
    candidate["active_work"]["current_task"] = "AIOS-P3-007_FAKE"
  end,
  "phase-local action drift" => lambda do |candidate|
    candidate["phase_execution_claim"]["phase_local_allowed"] = []
  end,
  "claim route drift" => lambda do |candidate|
    candidate["claim_boundary"]["current_phase_route"] = "OLD_ROUTE"
  end,
  "claim progress drift" => lambda do |candidate|
    candidate["claim_boundary"]["p3_delivery_progress_percent"] = 50
  end,
  "terminal P3-006 integration rewrite" => lambda do |candidate|
    candidate["claim_boundary"]["p3_006_candidate_integrated"] = true
  end,
  "long-term Goal drift" => lambda do |candidate|
    candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
  end
}

mutations.each do |label, mutation|
  expect_non_pass(root, truth, label, &mutation)
  assertions += 1
end

active_mutations = {
  "active Contract identity drift" => lambda do |candidate|
    candidate["active_work"]["current_task_contract"]["sha256"] = "0" * 64
  end,
  "active authority identity drift" => lambda do |candidate|
    candidate["active_work"]["authority_record"]["sha256"] = "0" * 64
  end,
  "active route task status drift" => lambda do |candidate|
    candidate["current_phase_route"]["active_task"]["status"] = "ACCEPTED"
  end,
  "active slot lifecycle drift" => lambda do |candidate|
    candidate["current_phase_route"]["ordered_slots"][0]["status"] = "ACCEPTED"
  end,
  "active ledger row drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"].last["status"] = "ACCEPTED"
  end,
  "active consumed budget drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["consumed"]["engineering_tasks"] = 6
  end,
  "active reservation drift" => lambda do |candidate|
    candidate["phase_execution_envelope"]["reserved"]["slot_id"] = "OTHER"
  end,
  "passed preactivation cannot revoke product write" => lambda do |candidate|
    candidate["active_work"]["preactivation"]["product_source_write_authorized"] = false
  end,
  "active branch drift" => lambda do |candidate|
    candidate["active_work"]["task_branch"] = "codex/other"
  end,
  "active action drift" => lambda do |candidate|
    candidate["phase_execution_claim"]["phase_local_allowed"] = ["IMPLEMENT_BEFORE_PREACTIVATION"]
  end,
  "active Task cannot create another Task" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_allowed"] = true
  end,
  "active claim cannot erase current Task" => lambda do |candidate|
    candidate["claim_boundary"]["current_task"] = "NONE"
  end,
  "active Goal cannot erase Task authority" => lambda do |candidate|
    candidate["goal"]["current_task_authority"] = "NONE"
  end,
  "active Task cannot enter P4" => lambda do |candidate|
    candidate["project"]["p4_entry_status"] = "AUTHORIZED"
  end,
  "active Task cannot rewrite P3-006 integration" => lambda do |candidate|
    candidate["claim_boundary"]["p3_006_candidate_integrated"] = true
  end
}

active_mutations.each do |label, mutation|
  expect_non_pass(root, active_truth, label, &mutation)
  assertions += 1
end

terminal_mutations = {
  "terminal Task cannot be rewritten PASS" => lambda do |candidate|
    candidate["current_phase_route"]["terminal_task"]["status"] = "ACCEPTED"
  end,
  "terminal security verdict cannot be rewritten" => lambda do |candidate|
    candidate["current_phase_route"]["terminal_task"]["independent_review_verdicts"]["security"] = "PASS"
  end,
  "terminal candidate cannot be marked integrated" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"].last["candidate"]["integrated"] = true
  end,
  "terminal receipt identity cannot drift" => lambda do |candidate|
    candidate["current_phase_route"]["terminal_task"]["terminal_receipt"]["sha256"] = "0" * 64
  end,
  "terminal slot cannot receive delivery credit" => lambda do |candidate|
    candidate["phase_execution_envelope"]["delivery_progress"]["percent"] = 75
  end,
  "terminal evaluation slot cannot unlock" => lambda do |candidate|
    candidate["phase_execution_envelope"]["ordered_slots"][1]["status"] = "ELIGIBLE_NOT_ACTIVATED"
  end,
  "terminal reserved budget cannot reappear" => lambda do |candidate|
    candidate["phase_execution_envelope"]["reserved"] = {"task_id" => "AIOS-P3-008_FAKE"}
  end,
  "terminal remaining capacity cannot become usable" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining_capacity_usable"] = true
  end,
  "terminal state cannot create a Task" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_allowed"] = true
  end,
  "terminal state cannot erase reserved trigger" => lambda do |candidate|
    candidate["founder_escalation_control"]["reserved_trigger"] = {
      "category" => "NONE", "evidence" => nil
    }
  end,
  "terminal active work cannot resurrect Task" => lambda do |candidate|
    candidate["active_work"]["current_task"] = P3FinalTransactionalRouteValidation::TASK_ID
  end,
  "terminal phase cannot schedule implementation" => lambda do |candidate|
    candidate["phase_execution_claim"]["phase_local_allowed"] = [
      P3FinalTransactionalRouteValidation::IMPLEMENT_ACTION
    ]
  end,
  "terminal claim cannot unlock evaluation" => lambda do |candidate|
    candidate["claim_boundary"]["p3_007_evaluation_slot_unlocked"] = true
  end,
  "terminal strict Exit cannot be accepted" => lambda do |candidate|
    items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
    items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
  end,
  "terminal Long-term Goal cannot close" => lambda do |candidate|
    candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
  end
}

terminal_mutations.each do |label, mutation|
  expect_non_pass(root, terminal_truth, label, &mutation)
  assertions += 1
end

hold_mutations = {
  "HOLD decision identity cannot drift" => lambda do |candidate|
    candidate["current_phase_route"]["founder_hold_decision"]["sha256"] = "0" * 64
  end,
  "HOLD cannot create a Task" => lambda do |candidate|
    candidate["phase_boundary"]["task_creation_allowed"] = true
  end,
  "HOLD cannot unlock remaining capacity" => lambda do |candidate|
    candidate["phase_execution_envelope"]["remaining_capacity_usable"] = true
  end,
  "HOLD cannot unlock evaluation" => lambda do |candidate|
    candidate["phase_execution_envelope"]["ordered_slots"][1]["status"] =
      "ELIGIBLE_NOT_ACTIVATED"
  end,
  "HOLD cannot accept strict Exit" => lambda do |candidate|
    items = candidate["strict_phase_gate_ledger"]["phases"]["P3"]["required_items"]
    items["RESUME_ISOLATION_PERMISSION_AND_TRACE_TESTS"]["status"] = "ACCEPTED"
  end,
  "HOLD cannot integrate rejected candidate" => lambda do |candidate|
    candidate["phase_execution_envelope"]["task_ledger"].last["candidate"]["integrated"] = true
  end,
  "HOLD cannot enter P4" => lambda do |candidate|
    candidate["project"]["p4_entry_status"] = "AUTHORIZED"
  end,
  "HOLD cannot close Long-term Goal" => lambda do |candidate|
    candidate["goal"]["control_plane_status_observed"] = "COMPLETE"
  end,
  "HOLD cannot request ordinary Founder action" => lambda do |candidate|
    candidate["founder_escalation_control"]["founder_decision_required"] = true
  end,
  "HOLD next action cannot drift" => lambda do |candidate|
    candidate["claim_boundary"]["next_eligible_action"] = "MASTER_CREATE_TASK"
  end
}

hold_mutations.each do |label, mutation|
  expect_non_pass(root, hold_truth, label, &mutation)
  assertions += 1
end

puts "P3_FINAL_TRANSACTIONAL_ROUTE_TEST: PASS #{assertions} assertions"

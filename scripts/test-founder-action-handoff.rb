#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "tmpdir"
require_relative "validate-founder-action-handoff"

ASSERTIONS = { count: 0 }

def write_fixture(package_bytes, draft, truth_bytes)
  Dir.mktmpdir("founder-handoff-test") do |root|
    truth = File.join(root, "truth.yaml")
    package_path = File.join(root, "package.json")
    draft_path = File.join(root, "draft.md")
    File.binwrite(truth, truth_bytes)
    File.binwrite(package_path, package_bytes)
    File.binwrite(draft_path, draft)
    yield truth, package_path, draft_path
  end
end

def assert_pass!(label, package, draft, truth_bytes,
                 user_token: package.dig("user_request_evidence", "exact_token"),
                 terminal_receipt_path: nil)
  ASSERTIONS[:count] += 1
  write_fixture(JSON.generate(package) + "\n", draft, truth_bytes) do |truth, package_path, draft_path|
    FounderActionHandoff.validate!(
      truth_path: truth, package_path: package_path, draft_path: draft_path, test_fixture: true,
      current_user_request_token: user_token, terminal_receipt_path: terminal_receipt_path
    )
  end
rescue StandardError => error
  abort "#{label}: expected PASS, got #{error.class}: #{error.message}"
end

def assert_reject!(label, package, draft, truth_bytes,
                   user_token: package.dig("user_request_evidence", "exact_token"),
                   terminal_receipt_path: nil)
  assert_raw_reject!(
    label, JSON.generate(package) + "\n", draft, truth_bytes,
    user_token: user_token, terminal_receipt_path: terminal_receipt_path
  )
end

def assert_raw_reject!(label, package_bytes, draft, truth_bytes, user_token: nil,
                       terminal_receipt_path: nil)
  ASSERTIONS[:count] += 1
  write_fixture(package_bytes, draft, truth_bytes) do |truth, package_path, draft_path|
    begin
      FounderActionHandoff.validate!(
        truth_path: truth, package_path: package_path, draft_path: draft_path, test_fixture: true,
        current_user_request_token: user_token, terminal_receipt_path: terminal_receipt_path
      )
    rescue FounderActionHandoff::ValidationError, KeyError, TypeError
      next
    end
    abort "#{label}: expected NON_PASS, got PASS"
  end
end

def terminal_handoff(receipt_path, receipt_bytes, next_step_user_action_required:, no_auto: true,
                     interpretation: FounderActionHandoff::TERMINAL_HANDOFF_INTERPRETATION)
  {
    "terminal_level" => "ROUTE",
    "terminal_status" => "TERMINAL_NON_PASS",
    "receipt_path" => receipt_path,
    "receipt_byte_length" => receipt_bytes.bytesize,
    "receipt_sha256" => Digest::SHA256.hexdigest(receipt_bytes),
    "no_automatic_successor_clause_present" => no_auto,
    "no_automatic_successor_interpretation" => no_auto ? interpretation : "NOT_APPLICABLE",
    "next_step_user_action_required" => next_step_user_action_required,
    "copy_ready_handoff_required" => true,
    "copy_ready_handoff_suppressed" => false
  }
end

def assert_terminal_result!(label, package, draft, truth_bytes, receipt_bytes,
                            next_step_user_action_required:, expect_pass:, interpretation: FounderActionHandoff::TERMINAL_HANDOFF_INTERPRETATION,
                            user_token: package.dig("user_request_evidence", "exact_token"))
  ASSERTIONS[:count] += 1
  Dir.mktmpdir("founder-terminal-handoff-test") do |root|
    truth = File.join(root, "truth.yaml")
    package_path = File.join(root, "package.json")
    draft_path = File.join(root, "draft.md")
    receipt_path = File.join(root, "terminal-receipt.json")
    bound_package = package.merge(
      "terminal_next_step_handoff" => terminal_handoff(
        receipt_path, receipt_bytes,
        next_step_user_action_required: next_step_user_action_required,
        interpretation: interpretation
      )
    )
    File.binwrite(truth, truth_bytes)
    File.binwrite(package_path, JSON.generate(bound_package) + "\n")
    File.binwrite(draft_path, draft)
    File.binwrite(receipt_path, receipt_bytes)
    begin
      FounderActionHandoff.validate!(
        truth_path: truth, package_path: package_path, draft_path: draft_path, test_fixture: true,
        current_user_request_token: user_token, terminal_receipt_path: receipt_path
      )
      abort "#{label}: expected NON_PASS, got PASS" unless expect_pass
    rescue FounderActionHandoff::ValidationError, KeyError, TypeError => error
      abort "#{label}: expected PASS, got #{error.class}: #{error.message}" if expect_pass
    end
  end
end

def truth_bytes(disposition: "NO_RESERVED_TRIGGER_CONTINUE_PHASE", decision: false,
                trigger: "NONE", owner: "MASTER_CEO_AGENT")
  <<~YAML
    project: SourceLens
    current_phase: P2
    founder_escalation_control:
      schema_version: founder-escalation-control/v1
      disposition: #{disposition}
      source_event:
        kind: TEST_CURRENT_STATE
        task_id:
        status: CURRENT
      reserved_trigger:
        category: #{trigger}
        evidence:
      phase_gate_status: NOT_ELIGIBLE_MISSING_REQUIRED_ITEMS
      founder_decision_required: #{decision}
      next_action_owner: #{owner}
      next_eligible_action: MASTER_SELECT_NEXT_INDEPENDENT_PHASE_LOCAL_TASK
  YAML
end

def identity(path)
  bytes = File.binread(File.join(FounderActionHandoff::ROOT, path))
  { "path" => path, "byte_length" => bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(bytes) }
end

def evidence(disposition: "NO_RESERVED_TRIGGER_CONTINUE_PHASE", decision: false,
             trigger: "NONE", owner: "MASTER_CEO_AGENT", prospective: nil)
  {
    "validator" => "scripts/validate-founder-delegation-continuity.rb",
    "command" => "ruby scripts/validate-founder-delegation-continuity.rb",
    "expected_disposition" => disposition,
    "expected_founder_decision_required" => decision,
    "expected_trigger" => trigger,
    "expected_next_action_owner" => owner,
    "prospective_preflight" => prospective
  }
end

def prospective_preflight(trigger: "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT", effect: "NETWORK")
  policy = identity("docs/aios/FOUNDER_DELEGATION_POLICY.md")
  {
    "status" => "PASS",
    "capability_gap" => FounderActionHandoff::PROSPECTIVE_PREFLIGHT,
    "current_disposition" => "NO_RESERVED_TRIGGER_CONTINUE_PHASE",
    "current_trigger" => "NONE",
    "requested_trigger" => trigger,
    "exact_external_effect" => effect,
    "policy_path" => policy["path"],
    "policy_byte_length" => policy["byte_length"],
    "policy_sha256" => policy["sha256"],
    "ordinary_task_failure_is_not_trigger" => true
  }
end

current_truth = truth_bytes
common = {
  "schema_version" => FounderActionHandoff::SCHEMA_VERSION,
  "truth_sha256" => Digest::SHA256.hexdigest(current_truth),
  "basis" => {
    "facts" => ["P2 remains active and incomplete."],
    "inferences" => [],
    "unknowns" => []
  },
  "affected_scope" => "Only the next bounded action is affected.",
  "project_authorized" => "YES",
  "app_filesystem_approval_required" => "NO",
  "write_not_executed" => "NOT_APPLICABLE",
  "agent_continuation_after_action" => "Continue the highest-value work within the verified authority.",
  "resume_condition" => "The declared action boundary is satisfied.",
  "safe_default" => "Preserve canonical source and do not exercise restricted effects.",
  "state_preservation" => "P2, the project, and the long-term Goal remain active.",
  "canonical_identity" => FounderActionHandoff.current_git_identity,
  "governing_artifact" => identity(FounderActionHandoff::RECOVERY_PLAN),
  "validator_evidence" => evidence,
  "user_request_evidence" => nil,
  "terminal_next_step_handoff" => nil
}

none = common.merge(
  "action_class" => "NONE_CONTINUE",
  "current_state" => "CONTINUING",
  "recommended_single_action" => "NONE",
  "copy_ready_text_or_exact_steps" => FounderActionHandoff::NO_ACTION_SENTENCE,
  "authorization" => nil,
  "material" => nil
)
none_draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: false
  RECOMMENDED_SINGLE_ACTION: NONE
  COPY_READY_TEXT_OR_EXACT_STEPS: #{FounderActionHandoff::NO_ACTION_SENTENCE}
  AGENT_CONTINUATION_AFTER_ACTION: #{none['agent_continuation_after_action']}
MARKDOWN
assert_pass!("no-action positive", none, none_draft, current_truth)
assert_reject!("no-action missing sentence", none,
               none_draft.sub(FounderActionHandoff::NO_ACTION_SENTENCE, "继续执行。"), current_truth)
assert_reject!("no-action contradictory request", none, none_draft + "USER_ACTION_REQUIRED: true\n", current_truth)
required_truth = truth_bytes(disposition: "FOUNDER_DECISION_REQUIRED", decision: true,
                             trigger: "PHASE_ENTRY_OR_EXIT", owner: "HUMAN_FOUNDER")
silenced = none.merge(
  "truth_sha256" => Digest::SHA256.hexdigest(required_truth),
  "validator_evidence" => evidence(disposition: "FOUNDER_DECISION_REQUIRED", decision: true,
                                   trigger: "PHASE_ENTRY_OR_EXIT", owner: "HUMAN_FOUNDER")
)
assert_reject!("required trigger silenced as no action", silenced, none_draft, required_truth)

canonical = common["canonical_identity"]
plan = common["governing_artifact"]
operation = FounderActionHandoff::READ_ONLY_HTTPS_OPERATION
method = FounderActionHandoff::READ_ONLY_HTTPS_METHOD
target = FounderActionHandoff::READ_ONLY_HTTPS_TARGETS
duration = "Single-use authorization"
budget = FounderActionHandoff::READ_ONLY_HTTPS_BUDGET
risk = "Read-only acquisition; stop before any non-allowlisted effect."
denial = "No network request is made and P2 remains active but blocked on source admission."
expiry = "Consumed by one acquisition attempt; no automatic successor."
pass_lifecycle = "PASS permits only benchmark input admission and no product or formal execution."
non_pass_lifecycle = "NON_PASS ends only this acquisition; P2, project, and long-term Goal remain active."
trigger = "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT"
copy_text = <<~TEXT.strip
  AUTHORIZE_EXACT_BOUNDED_NETWORK_V1；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{trigger}；operation type READ_ONLY_HTTPS_ACQUISITION；operation #{operation}；method #{method}；target #{target}；duration #{duration}；budget #{budget}；risk #{risk}；deny #{denial}；expiry #{expiry}；PASS #{pass_lifecycle}；NON_PASS #{non_pass_lifecycle}
TEXT
authorization = common.merge(
  "action_class" => "AUTHORIZATION_REQUIRED",
  "current_state" => "WAITING_USER",
  "project_authorized" => "NO",
  "write_not_executed" => "YES",
  "recommended_single_action" => "回复完整的受限网络授权文本",
  "copy_ready_text_or_exact_steps" => copy_text,
  "validator_evidence" => evidence(prospective: prospective_preflight),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => "AUTHORIZE_TEST_EXACT_BOUNDED_NETWORK_V1",
    "requested_external_effect" => "NETWORK"
  },
  "authorization" => {
    "authority_layer" => "FOUNDER_RESERVED",
    "operation_type" => "READ_ONLY_HTTPS_ACQUISITION",
    "reserved_trigger" => trigger,
    "proposal_mode" => "PROSPECTIVE_RESERVED_EFFECT",
    "recommended_decision" => "APPROVE",
    "grant_scope" => {
      "operations" => [operation, method],
      "targets" => [target],
      "duration" => duration,
      "budget_or_external_effects" => budget
    },
    "risk_and_reversibility" => risk,
    "deny_or_defer_effect" => denial,
    "authorization_expiry_or_consumption_rule" => expiry,
    "pass_lifecycle" => pass_lifecycle,
    "non_pass_lifecycle" => non_pass_lifecycle
  },
  "material" => nil
)
draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: true
  RECOMMENDED_SINGLE_ACTION: #{authorization['recommended_single_action']}
  COPY_READY_TEXT_OR_EXACT_STEPS: #{copy_text}
  AGENT_CONTINUATION_AFTER_ACTION: #{authorization['agent_continuation_after_action']}
MARKDOWN
assert_pass!("authorization positive", authorization, draft, current_truth)

terminal_receipt = JSON.generate(
  "schema" => "test.route-terminal-receipt/v1",
  "verdict" => "TERMINAL_NON_PASS",
  "no_automatic_successor" => true
) + "\n"
assert_terminal_result!("terminal no-auto clause still delivers required authorization",
                        authorization, draft, current_truth, terminal_receipt,
                        next_step_user_action_required: true, expect_pass: true)
assert_terminal_result!("terminal reserved next step cannot be silenced as no action",
                        none, none_draft, current_truth, terminal_receipt,
                        next_step_user_action_required: true, expect_pass: false, user_token: nil)
assert_terminal_result!("terminal no-auto clause cannot suppress handoff by interpretation",
                        authorization, draft, current_truth, terminal_receipt,
                        next_step_user_action_required: true, expect_pass: false,
                        interpretation: "NO_AUTOMATIC_SUCCESSOR_SUPPRESSES_NEXT_AUTHORIZATION")
assert_terminal_result!("terminal Phase-local continuation needs no Founder authorization",
                        none, none_draft, current_truth, terminal_receipt,
                        next_step_user_action_required: false, expect_pass: true, user_token: nil)

route_terminal_truth = truth_bytes(
  disposition: "NO_RESERVED_TRIGGER_ROUTE_TERMINAL", decision: false,
  trigger: "NONE", owner: "NONE"
)
route_terminal_none = none.merge(
  "truth_sha256" => Digest::SHA256.hexdigest(route_terminal_truth),
  "validator_evidence" => evidence(
    disposition: "NO_RESERVED_TRIGGER_ROUTE_TERMINAL", decision: false,
    trigger: "NONE", owner: "NONE"
  )
)
assert_terminal_result!("terminal no-action Route cannot deadlock an incomplete project at owner NONE",
                        route_terminal_none, none_draft, route_terminal_truth, terminal_receipt,
                        next_step_user_action_required: false, expect_pass: false, user_token: nil)

standard_operation = "一次全新、独立、clean-room V7 benchmark source acquisition using exact system curl"
standard_budget = FounderActionHandoff::STANDARD_CURL_BUDGET
standard_exclusions = FounderActionHandoff::STANDARD_CURL_METRIC_EXCLUSIONS
standard_retry = FounderActionHandoff::STANDARD_CURL_RETRY_POLICY
standard_curl_binding = FounderActionHandoff::STANDARD_CURL_IDENTITY_BINDING
standard_copy_text = <<~TEXT.strip
  AUTHORIZE_P2_BENCHMARK_SOURCE_ACQUISITION_CLEAN_ROOM_CURATOR_V7_STANDARD_CURL_V1；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{trigger}；operation type READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL；operation #{standard_operation}；method #{method}；metric exclusions #{standard_exclusions}；retry policy #{standard_retry}；curl binding #{standard_curl_binding}；target #{target}；duration #{duration}；budget #{standard_budget}；risk #{risk}；deny #{denial}；expiry #{expiry}；PASS #{pass_lifecycle}；NON_PASS #{non_pass_lifecycle}
TEXT
standard_authorization = authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_copy_text,
  "authorization" => authorization["authorization"].merge(
    "operation_type" => "READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL",
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [standard_operation, method, standard_exclusions, standard_retry, standard_curl_binding],
      "budget_or_external_effects" => standard_budget
    )
  )
)
standard_draft = draft.sub(copy_text, standard_copy_text)
assert_pass!("standard-curl authorization positive", standard_authorization, standard_draft, current_truth)

milestone_operation = FounderActionHandoff::MILESTONE_CURL_OPERATION
milestone_method = FounderActionHandoff::MILESTONE_CURL_METHOD
milestone_copy = <<~TEXT.strip
  #{FounderActionHandoff::MILESTONE_CURL_TOKEN}；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{trigger}；operation type READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL；operation #{milestone_operation}；method #{milestone_method}；metric exclusions #{standard_exclusions}；retry policy #{standard_retry}；curl binding #{standard_curl_binding}；target #{target}；duration #{FounderActionHandoff::MILESTONE_CURL_DURATION}；budget #{FounderActionHandoff::MILESTONE_CURL_BUDGET}；risk #{risk}；deny #{denial}；expiry #{FounderActionHandoff::MILESTONE_CURL_CONSUMPTION}；PASS #{FounderActionHandoff::MILESTONE_CURL_PASS}；NON_PASS #{FounderActionHandoff::MILESTONE_CURL_NON_PASS}
TEXT
milestone_authorization = authorization.merge(
  "copy_ready_text_or_exact_steps" => milestone_copy,
  "authorization" => authorization["authorization"].merge(
    "operation_type" => "READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL",
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [milestone_operation, milestone_method, standard_exclusions, standard_retry, standard_curl_binding],
      "duration" => FounderActionHandoff::MILESTONE_CURL_DURATION,
      "budget_or_external_effects" => FounderActionHandoff::MILESTONE_CURL_BUDGET
    ),
    "authorization_expiry_or_consumption_rule" => FounderActionHandoff::MILESTONE_CURL_CONSUMPTION,
    "pass_lifecycle" => FounderActionHandoff::MILESTONE_CURL_PASS,
    "non_pass_lifecycle" => FounderActionHandoff::MILESTONE_CURL_NON_PASS
  )
)
milestone_draft = standard_draft.sub(standard_copy_text, milestone_copy)
assert_pass!("milestone-curl authorization positive", milestone_authorization, milestone_draft, current_truth)

reissue_operation = FounderActionHandoff::MILESTONE_CURL_REISSUE_OPERATION
reissue_method = FounderActionHandoff::MILESTONE_CURL_REISSUE_METHOD
reissue_copy = <<~TEXT.strip
  #{FounderActionHandoff::MILESTONE_CURL_REISSUE_TOKEN}；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{trigger}；operation type READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL_REISSUE；operation #{reissue_operation}；method #{reissue_method}；metric exclusions #{standard_exclusions}；retry policy #{standard_retry}；curl binding #{standard_curl_binding}；target #{target}；duration #{FounderActionHandoff::MILESTONE_CURL_REISSUE_DURATION}；budget #{FounderActionHandoff::MILESTONE_CURL_REISSUE_BUDGET}；risk #{risk}；deny #{denial}；expiry #{FounderActionHandoff::MILESTONE_CURL_REISSUE_CONSUMPTION}；PASS #{FounderActionHandoff::MILESTONE_CURL_REISSUE_PASS}；NON_PASS #{FounderActionHandoff::MILESTONE_CURL_REISSUE_NON_PASS}
TEXT
reissue_authorization = authorization.merge(
  "copy_ready_text_or_exact_steps" => reissue_copy,
  "user_request_evidence" => authorization["user_request_evidence"].merge(
    "exact_token" => FounderActionHandoff::MILESTONE_CURL_TOKEN
  ),
  "authorization" => authorization["authorization"].merge(
    "operation_type" => "READ_ONLY_HTTPS_BENCHMARK_SOURCE_MILESTONE_STANDARD_CURL_REISSUE",
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [reissue_operation, reissue_method, standard_exclusions, standard_retry, standard_curl_binding],
      "duration" => FounderActionHandoff::MILESTONE_CURL_REISSUE_DURATION,
      "budget_or_external_effects" => FounderActionHandoff::MILESTONE_CURL_REISSUE_BUDGET
    ),
    "authorization_expiry_or_consumption_rule" => FounderActionHandoff::MILESTONE_CURL_REISSUE_CONSUMPTION,
    "pass_lifecycle" => FounderActionHandoff::MILESTONE_CURL_REISSUE_PASS,
    "non_pass_lifecycle" => FounderActionHandoff::MILESTONE_CURL_REISSUE_NON_PASS
  )
)
reissue_draft = standard_draft.sub(standard_copy_text, reissue_copy)
assert_pass!("milestone-curl reissue authorization positive", reissue_authorization, reissue_draft, current_truth)

completion_trigger = "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
completion_operation = FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_OPERATION
completion_method = FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_METHOD
completion_request_token = "每次终态都交付下一步授权"
completion_copy = <<~TEXT.strip
  #{FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_TOKEN}；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{completion_trigger}；operation type P2_BENCHMARK_SOURCE_FINAL_CANDIDATE_COMPLETION_ENVELOPE；operation #{completion_operation}；method #{completion_method}；metric exclusions #{standard_exclusions}；retry policy #{standard_retry}；curl binding #{standard_curl_binding}；target #{target}；duration #{FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_DURATION}；budget #{FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_BUDGET}；risk #{risk}；deny #{denial}；expiry #{FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_CONSUMPTION}；PASS #{FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_PASS}；NON_PASS #{FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_NON_PASS}
TEXT
completion_authorization = authorization.merge(
  "copy_ready_text_or_exact_steps" => completion_copy,
  "validator_evidence" => evidence(prospective: prospective_preflight(trigger: completion_trigger, effect: "MATERIAL_SCOPE")),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => completion_request_token,
    "requested_external_effect" => "MATERIAL_SCOPE"
  },
  "authorization" => authorization["authorization"].merge(
    "operation_type" => "P2_BENCHMARK_SOURCE_FINAL_CANDIDATE_COMPLETION_ENVELOPE",
    "reserved_trigger" => completion_trigger,
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [completion_operation, completion_method, standard_exclusions, standard_retry, standard_curl_binding],
      "duration" => FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_DURATION,
      "budget_or_external_effects" => FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_BUDGET
    ),
    "authorization_expiry_or_consumption_rule" => FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_CONSUMPTION,
    "pass_lifecycle" => FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_PASS,
    "non_pass_lifecycle" => FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_NON_PASS
  )
)
completion_draft = standard_draft.sub(standard_copy_text, completion_copy)
assert_pass!("final candidate completion envelope positive", completion_authorization, completion_draft,
             current_truth, user_token: completion_request_token)

resequence_trigger = "MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE"
resequence_request_token = "下一步我应该做什么？应该授权哪些内容？"
resequence_risk = "One bounded local capacity expansion and scheduling replacement; all prior consumption and terminal facts remain immutable, and all external effects remain prohibited."
resequence_denial = "Do not create another P2 Task; keep P2 and the long-term Goal active, P3 HOLD, strict progress zero, and preserve P2-068 terminal Evidence."
resequence_copy = <<~TEXT.strip
  #{FounderActionHandoff::RECOVERY_RESEQUENCE_TOKEN}；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{resequence_trigger}；operation type P2_RECOVERY_CLEAN_ROOM_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION；operation #{FounderActionHandoff::RECOVERY_RESEQUENCE_OPERATION}；order #{FounderActionHandoff::RECOVERY_RESEQUENCE_ORDER}；lineage #{FounderActionHandoff::RECOVERY_RESEQUENCE_LINEAGE}；target #{FounderActionHandoff::RECOVERY_RESEQUENCE_TARGET}；duration #{FounderActionHandoff::RECOVERY_RESEQUENCE_DURATION}；budget #{FounderActionHandoff::RECOVERY_RESEQUENCE_BUDGET}；risk #{resequence_risk}；deny #{resequence_denial}；expiry #{FounderActionHandoff::RECOVERY_RESEQUENCE_CONSUMPTION}；PASS #{FounderActionHandoff::RECOVERY_RESEQUENCE_PASS}；NON_PASS #{FounderActionHandoff::RECOVERY_RESEQUENCE_NON_PASS}
TEXT
resequence_authorization = authorization.merge(
  "copy_ready_text_or_exact_steps" => resequence_copy,
  "validator_evidence" => evidence(
    prospective: prospective_preflight(trigger: resequence_trigger, effect: "MATERIAL_SCOPE")
  ),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => resequence_request_token,
    "requested_external_effect" => "MATERIAL_SCOPE"
  },
  "authorization" => authorization.fetch("authorization").merge(
    "operation_type" => "P2_RECOVERY_CLEAN_ROOM_RESEQUENCING_AND_MINIMAL_ENVELOPE_EXPANSION",
    "reserved_trigger" => resequence_trigger,
    "grant_scope" => {
      "operations" => [
        FounderActionHandoff::RECOVERY_RESEQUENCE_OPERATION,
        FounderActionHandoff::RECOVERY_RESEQUENCE_ORDER,
        FounderActionHandoff::RECOVERY_RESEQUENCE_LINEAGE
      ],
      "targets" => [FounderActionHandoff::RECOVERY_RESEQUENCE_TARGET],
      "duration" => FounderActionHandoff::RECOVERY_RESEQUENCE_DURATION,
      "budget_or_external_effects" => FounderActionHandoff::RECOVERY_RESEQUENCE_BUDGET
    },
    "risk_and_reversibility" => resequence_risk,
    "deny_or_defer_effect" => resequence_denial,
    "authorization_expiry_or_consumption_rule" => FounderActionHandoff::RECOVERY_RESEQUENCE_CONSUMPTION,
    "pass_lifecycle" => FounderActionHandoff::RECOVERY_RESEQUENCE_PASS,
    "non_pass_lifecycle" => FounderActionHandoff::RECOVERY_RESEQUENCE_NON_PASS
  )
)
resequence_draft = standard_draft.sub(standard_copy_text, resequence_copy)
assert_pass!("clean-room recovery resequencing positive", resequence_authorization,
             resequence_draft, current_truth, user_token: resequence_request_token)
resequence_reset_budget = "Reset all consumed P2 capacity and add three fresh Tasks"
assert_reject!(
  "clean-room recovery resequencing rejects consumed-capacity reset",
  resequence_authorization.merge(
    "copy_ready_text_or_exact_steps" => resequence_copy.sub(
      FounderActionHandoff::RECOVERY_RESEQUENCE_BUDGET, resequence_reset_budget
    ),
    "authorization" => resequence_authorization.fetch("authorization").merge(
      "grant_scope" => resequence_authorization.dig("authorization", "grant_scope").merge(
        "budget_or_external_effects" => resequence_reset_budget
      )
    )
  ),
  resequence_draft.sub(FounderActionHandoff::RECOVERY_RESEQUENCE_BUDGET, resequence_reset_budget),
  current_truth,
  user_token: resequence_request_token
)

completion_reset_budget = "A fresh 5 GiB body budget that resets all prior consumption"
completion_reset_copy = completion_copy.sub(FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_BUDGET,
                                             completion_reset_budget)
assert_reject!("final candidate completion rejects ledger reset",
               completion_authorization.merge(
                 "copy_ready_text_or_exact_steps" => completion_reset_copy,
                 "authorization" => completion_authorization["authorization"].merge(
                   "grant_scope" => completion_authorization.dig("authorization", "grant_scope").merge(
                     "budget_or_external_effects" => completion_reset_budget
                   )
                 )
               ), completion_draft.sub(completion_copy, completion_reset_copy), current_truth,
               user_token: completion_request_token)
completion_route_copy = completion_copy.sub(FounderActionHandoff::FINAL_CANDIDATE_COMPLETION_TOKEN,
                                             "AUTHORIZE_P2_BENCHMARK_SOURCE_ACQUISITION_CLEAN_ROOM_CURATOR_V145_STANDARD_CURL_V1")
assert_reject!("final candidate completion rejects numbered Route token",
               completion_authorization.merge("copy_ready_text_or_exact_steps" => completion_route_copy),
               completion_draft.sub(completion_copy, completion_route_copy), current_truth,
               user_token: completion_request_token)

assert_reject!("V1 terminal context rejects original milestone V1 profile",
               milestone_authorization.merge(
                 "user_request_evidence" => milestone_authorization["user_request_evidence"].merge(
                   "exact_token" => FounderActionHandoff::MILESTONE_CURL_TOKEN
                 )
               ), milestone_draft, current_truth,
               user_token: FounderActionHandoff::MILESTONE_CURL_TOKEN)
v13_standard_copy = standard_copy_text.sub("CURATOR_V7_STANDARD_CURL", "CURATOR_V13_STANDARD_CURL")
                                         .sub(standard_operation, standard_operation.sub(" V7 ", " V13 "))
v13_standard = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => v13_standard_copy,
  "user_request_evidence" => standard_authorization["user_request_evidence"].merge(
    "exact_token" => FounderActionHandoff::MILESTONE_CURL_TOKEN
  ),
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [standard_operation.sub(" V7 ", " V13 "), method, standard_exclusions, standard_retry, standard_curl_binding]
    )
  )
)
assert_reject!("V1 terminal context rejects legacy V13 route profile", v13_standard,
               standard_draft.sub(standard_copy_text, v13_standard_copy), current_truth,
               user_token: FounderActionHandoff::MILESTONE_CURL_TOKEN)
%w[V13 V14].each do |version|
  route_token_copy = reissue_copy.sub(FounderActionHandoff::MILESTONE_CURL_REISSUE_TOKEN,
                                      "AUTHORIZE_P2_BENCHMARK_SOURCE_ACQUISITION_CLEAN_ROOM_CURATOR_#{version}_STANDARD_CURL_V1")
  route_token_package = reissue_authorization.merge("copy_ready_text_or_exact_steps" => route_token_copy)
  assert_reject!("milestone reissue rejects #{version} route token", route_token_package,
                 reissue_draft.sub(reissue_copy, route_token_copy), current_truth)
end
reissue_per_route_budget = reissue_copy.sub(FounderActionHandoff::MILESTONE_CURL_REISSUE_BUDGET,
                                             "A fresh 4 GiB body budget per independent Route")
assert_reject!("milestone reissue rejects per-route budget reset",
               reissue_authorization.merge(
                 "copy_ready_text_or_exact_steps" => reissue_per_route_budget,
                 "authorization" => reissue_authorization["authorization"].merge(
                   "grant_scope" => reissue_authorization.dig("authorization", "grant_scope").merge(
                     "budget_or_external_effects" => "A fresh 4 GiB body budget per independent Route"
                   )
                 )
               ), reissue_draft.sub(reissue_copy, reissue_per_route_budget), current_truth)
milestone_route_token = milestone_authorization.merge(
  "authorization" => milestone_authorization["authorization"].merge(
    "grant_scope" => milestone_authorization.dig("authorization", "grant_scope").merge(
      "operations" => milestone_authorization.dig("authorization", "grant_scope", "operations").dup.tap { |values| values[0] = "一次全新、独立、clean-room V13 benchmark source acquisition using exact system curl" }
    )
  )
)
assert_reject!("milestone profile rejects numbered route operation", milestone_route_token, milestone_draft, current_truth)
%w[V13 V14].each do |version|
  route_token_copy = milestone_copy.sub(FounderActionHandoff::MILESTONE_CURL_TOKEN, "AUTHORIZE_P2_BENCHMARK_SOURCE_ACQUISITION_CLEAN_ROOM_CURATOR_#{version}_STANDARD_CURL_V1")
  route_token_package = milestone_authorization.merge("copy_ready_text_or_exact_steps" => route_token_copy)
  assert_reject!("milestone profile rejects #{version} route token", route_token_package,
                 milestone_draft.sub(milestone_copy, route_token_copy), current_truth)
end
{
  "milestone profile rejects single-route duration" => ["grant_scope", "duration", "Single-use authorization"],
  "milestone profile rejects per-route budget reset" => ["grant_scope", "budget_or_external_effects", "4,294,967,296 CREATE_ONCE_PERSISTED_HTTP_RESPONSE_BODY_OCTETS per Route"],
  "milestone profile rejects route consumption" => ["authorization_expiry_or_consumption_rule", nil, "Consumed by one acquisition attempt"],
  "milestone profile rejects PASS extension" => ["pass_lifecycle", nil, "PASS continues the capability after P2"],
  "milestone profile rejects route terminal nonpass" => ["non_pass_lifecycle", nil, "NON_PASS terminates this capability and requires a new route authorization."]
}.each do |label, (field, nested, value)|
  mutated_auth = milestone_authorization["authorization"].dup
  if field == "grant_scope"
    mutated_auth[field] = mutated_auth[field].merge(nested => value)
  else
    mutated_auth[field] = value
  end
  original = if field == "grant_scope"
               nested == "duration" ? FounderActionHandoff::MILESTONE_CURL_DURATION : FounderActionHandoff::MILESTONE_CURL_BUDGET
             elsif field == "authorization_expiry_or_consumption_rule"
               FounderActionHandoff::MILESTONE_CURL_CONSUMPTION
             elsif field == "pass_lifecycle"
               FounderActionHandoff::MILESTONE_CURL_PASS
             else
               FounderActionHandoff::MILESTONE_CURL_NON_PASS
             end
  mutated_copy = milestone_copy.sub(
    original, value
  )
  mutated_package = milestone_authorization.merge("authorization" => mutated_auth, "copy_ready_text_or_exact_steps" => mutated_copy)
  assert_reject!(label, mutated_package, milestone_draft.sub(milestone_copy, mutated_copy), current_truth)
end

standard_v8_operation = standard_operation.sub(" V7 ", " V8 ")
standard_v8_copy = standard_copy_text.sub("CURATOR_V7_STANDARD_CURL", "CURATOR_V8_STANDARD_CURL")
                                      .sub(standard_operation, standard_v8_operation)
standard_v8 = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_v8_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [standard_v8_operation, method, standard_exclusions, standard_retry, standard_curl_binding]
    )
  )
)
assert_pass!("standard-curl data-driven V8 positive", standard_v8,
             standard_draft.sub(standard_copy_text, standard_v8_copy), current_truth)

standard_v8_wrong_copy = standard_v8_copy.sub("CURATOR_V8_STANDARD_CURL", "CURATOR_V9_STANDARD_CURL")
standard_v8_wrong_token = standard_v8.merge("copy_ready_text_or_exact_steps" => standard_v8_wrong_copy)
assert_reject!("standard-curl operation and token version mismatch", standard_v8_wrong_token,
               standard_draft.sub(standard_copy_text, standard_v8_wrong_copy), current_truth)

standard_v1_operation = standard_operation.sub(" V7 ", " V1 ")
standard_v1_copy = standard_copy_text.sub(standard_operation, standard_v1_operation)
standard_v1_wrong_semantic_position = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_v1_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [standard_v1_operation, method, standard_exclusions, standard_retry, standard_curl_binding]
    )
  )
)
assert_reject!("standard-curl token schema suffix cannot impersonate acquisition version",
               standard_v1_wrong_semantic_position,
               standard_draft.sub(standard_copy_text, standard_v1_copy), current_truth)

ambiguous_version_token = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_copy_text.sub(
    "CURATOR_V7_STANDARD_CURL", "CURATOR_V7_STANDARD_CURL_CURATOR_V8_STANDARD_CURL"
  )
)
assert_reject!("standard-curl token cannot contain multiple acquisition versions",
               ambiguous_version_token,
               standard_draft.sub(standard_copy_text, ambiguous_version_token["copy_ready_text_or_exact_steps"]),
               current_truth)

standard_raw_budget_copy = standard_copy_text.sub(standard_budget, budget)
standard_raw_budget = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_raw_budget_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "budget_or_external_effects" => budget
    )
  )
)
assert_reject!("standard-curl enum with raw-TCP budget contradiction", standard_raw_budget,
               standard_draft.sub(standard_copy_text, standard_raw_budget_copy), current_truth)

standard_v6_operation_copy = standard_copy_text.sub(standard_operation, operation)
standard_v6_operation = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_v6_operation_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [operation, method, standard_exclusions, standard_retry, standard_curl_binding]
    )
  )
)
assert_reject!("standard-curl enum with V6 operation", standard_v6_operation,
               standard_draft.sub(standard_copy_text, standard_v6_operation_copy), current_truth)

non_v7_operation = standard_operation.sub(" V7 ", " V8 ")
non_v7_operation_copy = standard_copy_text.sub(standard_operation, non_v7_operation)
non_v7_operation_package = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => non_v7_operation_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [non_v7_operation, method, standard_exclusions, standard_retry, standard_curl_binding]
    )
  )
)
assert_reject!("standard-curl enum with non-V7 operation", non_v7_operation_package,
               standard_draft.sub(standard_copy_text, non_v7_operation_copy), current_truth)

generic_operation = standard_operation.sub(" V7", "")
generic_operation_copy = standard_copy_text.sub(standard_operation, generic_operation)
generic_operation_package = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => generic_operation_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [generic_operation, method, standard_exclusions, standard_retry, standard_curl_binding]
    )
  )
)
assert_reject!("standard-curl enum with generic operation", generic_operation_package,
               standard_draft.sub(standard_copy_text, generic_operation_copy), current_truth)

standard_without_exclusions_copy = standard_copy_text.sub("；metric exclusions #{standard_exclusions}", "")
standard_without_exclusions = standard_authorization.merge(
  "copy_ready_text_or_exact_steps" => standard_without_exclusions_copy,
  "authorization" => standard_authorization["authorization"].merge(
    "grant_scope" => standard_authorization.dig("authorization", "grant_scope").merge(
      "operations" => [standard_operation, method, standard_retry, standard_curl_binding]
    )
  )
)
assert_reject!("standard-curl scope omits metric exclusions", standard_without_exclusions,
               standard_draft.sub(standard_copy_text, standard_without_exclusions_copy), current_truth)

assert_reject!("authorization missing copy-ready text", authorization,
               draft.sub(copy_text, "请批准下一步。"), current_truth)
assert_reject!("authorization placeholder", authorization,
               draft + "补充：TBD\n", current_truth)
assert_reject!("authorization Truth drift", authorization.merge("truth_sha256" => "0" * 64), draft, current_truth)
assert_reject!("authorization missing trigger", authorization.merge(
  "authorization" => authorization["authorization"].merge("reserved_trigger" => nil)
), draft, current_truth)
assert_reject!("authorization bundles material", authorization.merge("material" => {}), draft, current_truth)
assert_reject!("prospective preflight absent", authorization.merge(
  "validator_evidence" => evidence
), draft, current_truth)
assert_reject!("prospective direct-user request absent", authorization.merge(
  "user_request_evidence" => nil
), draft, current_truth)
assert_reject!("prospective direct-user request mismatch", authorization, draft, current_truth,
               user_token: "AUTHORIZE_DIFFERENT_REQUEST_V1")
ordinary_operation = "Repair an ordinary implementation test"
ordinary_copy = copy_text.sub(operation, ordinary_operation)
ordinary = authorization.merge(
  "copy_ready_text_or_exact_steps" => ordinary_copy,
  "authorization" => authorization["authorization"].merge(
    "operation_type" => "ORDINARY_LOCAL_TEST_REPAIR",
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [ordinary_operation]
    )
  )
)
ordinary_draft = draft.sub(copy_text, ordinary_copy)
assert_reject!("ordinary blocker disguised as prospective effect", ordinary, ordinary_draft, current_truth)
ordinary_no_network = "Repair an ordinary implementation test with no network access"
ordinary_no_network_target = "Local source only"
ordinary_no_network_budget = "No network or external effects; zero bytes"
ordinary_no_network_copy = copy_text.sub(operation, ordinary_no_network)
                                    .sub(target, ordinary_no_network_target)
                                    .sub(budget, ordinary_no_network_budget)
ordinary_no_network_package = authorization.merge(
  "copy_ready_text_or_exact_steps" => ordinary_no_network_copy,
  "authorization" => authorization["authorization"].merge(
    "operation_type" => "ORDINARY_LOCAL_TEST_REPAIR",
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [ordinary_no_network],
      "targets" => [ordinary_no_network_target],
      "budget_or_external_effects" => ordinary_no_network_budget
    )
  )
)
assert_reject!("ordinary no-network blocker false escalation", ordinary_no_network_package,
               draft.sub(copy_text, ordinary_no_network_copy), current_truth)
ordinary_contradiction_copy = copy_text.sub(operation, ordinary_no_network)
                                      .sub(method, "No HTTPS request is allowed")
                                      .sub(target, ordinary_no_network_target)
                                      .sub(budget, ordinary_no_network_budget)
ordinary_contradiction = authorization.merge(
  "copy_ready_text_or_exact_steps" => ordinary_contradiction_copy,
  "authorization" => authorization["authorization"].merge(
    "grant_scope" => authorization.dig("authorization", "grant_scope").merge(
      "operations" => [ordinary_no_network, "No HTTPS request is allowed"],
      "targets" => [ordinary_no_network_target],
      "budget_or_external_effects" => ordinary_no_network_budget
    )
  )
)
assert_reject!("valid network enum contradicts ordinary local scope", ordinary_contradiction,
               draft.sub(copy_text, ordinary_contradiction_copy), current_truth)
assert_reject!("authorization missing canonical identity in copy", authorization,
               draft.sub(canonical["commit"], "commit omitted"), current_truth)
assert_reject!("authorization second action", authorization,
               draft + "RECOMMENDED_SINGLE_ACTION: 另一个动作\n", current_truth)
assert_reject!("authorization indented second action", authorization,
               draft + "  RECOMMENDED_SINGLE_ACTION: UPLOAD_LOCAL_ARCHIVE_INSTEAD\n", current_truth)
assert_reject!("authorization prose second action", authorization,
               draft + "另一个动作：请上传本地 archive。\n", current_truth)
assert_reject!("authorization production-release second action", authorization,
               draft + "另外，请同时批准生产发布。\n", current_truth)
assert_reject!("authorization second token", authorization,
               draft + "AUTHORIZE_ANOTHER_ACTION_V1；\n", current_truth)
assert_reject!("authorization second token before period", authorization,
               draft + "AUTHORIZE_ANOTHER_ACTION_V1.\n", current_truth)
assert_reject!("authorization second token in parentheses", authorization,
               draft + "(AUTHORIZE_ANOTHER_ACTION_V1)\n", current_truth)
assert_reject!("authorization second token at EOF", authorization,
               draft + "AUTHORIZE_ANOTHER_ACTION_V1", current_truth)
assert_reject!("authorization second token in backticks", authorization,
               draft + "`AUTHORIZE_ANOTHER_ACTION_V1`\n", current_truth)
duplicate_json = JSON.generate(authorization).sub(/\A\{/, '{"schema_version":"forged",') + "\n"
assert_raw_reject!("duplicate JSON key", duplicate_json, draft, current_truth)

app = authorization.merge(
  "project_authorized" => "YES",
  "app_filesystem_approval_required" => "YES",
  "authorization" => authorization["authorization"].merge(
    "authority_layer" => "APP_FILESYSTEM", "reserved_trigger" => nil,
    "proposal_mode" => "NOT_APPLICABLE", "operation_type" => "APP_FILESYSTEM_BATCH_WRITE"
  ),
  "validator_evidence" => evidence
)
assert_reject!("App approval contains Founder token", app, draft, current_truth)
mixed_app = app.merge(
  "copy_ready_text_or_exact_steps" => app["copy_ready_text_or_exact_steps"].sub("AUTHORIZE_", "Authorize_")
)
assert_reject!("App approval contains mixed-case Founder token", mixed_app,
               draft.sub("AUTHORIZE_", "Authorize_"), current_truth)

material_copy = "请上传 P2 benchmark source-pack archive；来源 Founder-authorized current pack；格式 One tar archive plus SHA-256 manifest；最低完整度 Six repositories, twelve tasks, licenses, base/fix identities and tests；提交 Attach the archive to this Codex task or provide an exact local path.；校验 Closed inventory, SHA-256, licensing and offline test admission must pass.；替代 A fresh bounded network acquisition authorization."
material = common.merge(
  "action_class" => "MATERIAL_REQUIRED",
  "current_state" => "WAITING_USER",
  "write_not_executed" => "YES",
  "recommended_single_action" => "上传唯一的离线 source-pack archive",
  "copy_ready_text_or_exact_steps" => material_copy,
  "authorization" => nil,
  "material" => {
    "required_items" => [{
      "name" => "P2 benchmark source-pack archive",
      "source_or_version" => "Founder-authorized current pack",
      "format" => "One tar archive plus SHA-256 manifest",
      "minimum_completeness" => "Six repositories, twelve tasks, licenses, base/fix identities and tests"
    }],
    "why_agent_cannot_obtain_it" => "No network authorization or equivalent local source pack exists.",
    "submission_channel" => "Attach the archive to this Codex task or provide an exact local path.",
    "redaction_allowed" => "Secrets must be removed; public source and license identities must remain.",
    "validation_rule" => "Closed inventory, SHA-256, licensing and offline test admission must pass.",
    "acceptable_alternative" => "A fresh bounded network acquisition authorization."
  }
)
material_draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: true
  RECOMMENDED_SINGLE_ACTION: #{material['recommended_single_action']}
  COPY_READY_TEXT_OR_EXACT_STEPS: #{material_copy}
  AGENT_CONTINUATION_AFTER_ACTION: #{material['agent_continuation_after_action']}
MARKDOWN
assert_pass!("material positive", material, material_draft, current_truth)
assert_reject!("material vague item", material.merge(
  "material" => material["material"].merge("required_items" => [])
), material_draft, current_truth)
assert_reject!("material bundles authorization", material.merge("authorization" => {}), material_draft, current_truth)

p3_host_authorized_truth = truth_bytes(
  disposition: "FOUNDER_RESERVED_DECISION_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD",
  decision: false,
  trigger: FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER,
  owner: "NONE"
)
p3_host_authorized_body = File.binread(
  "/Users/lijunpeng/.codex/attachments/9b6253cf-5837-4efc-8738-a9396f1bfaf2/pasted-text.txt"
).force_encoding("UTF-8")
abort "P3 host-authorized Founder body fixture encoding invalid" unless p3_host_authorized_body.valid_encoding?
p3_host_authorized_profile = FounderActionHandoff::FOUNDER_NETWORK_OPERATION_PROFILES.fetch(
  "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007"
)
p3_host_authorized_risk = "该 Objective 取代 v2.6 中“Agent state-specific typed payload → fixed host transition handler”这一已经耗尽的具体实现假设，但不降低 Minimum Trust 或 strict Exit Gate。"
p3_host_authorized_deny = "network、Provider、Secret；"
p3_host_authorized = common.merge(
  "canonical_identity" => {
    "commit" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_COMMIT,
    "tree" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TREE,
    "branch" => "main"
  },
  "truth_sha256" => Digest::SHA256.hexdigest(p3_host_authorized_truth),
  "basis" => {
    "facts" => ["P3 is in the exact Founder-resolved strategic HOLD after P3-007 terminal NON_PASS."],
    "inferences" => [],
    "unknowns" => []
  },
  "affected_scope" => "Only the P3 Objective, three-stage route and non-resettable Phase ceiling are rebaselined.",
  "project_authorized" => "NO",
  "app_filesystem_approval_required" => "NO",
  "write_not_executed" => "YES",
  "agent_continuation_after_action" => "Install Constitution v2.7, the exact route, Truth projection and validators with zero engineering progress, then activate only Stage 1 after independent installation audit PASS.",
  "resume_condition" => "The complete exact Founder body is directly supplied and every bound current identity passes revalidation.",
  "safe_default" => "Keep the preinstallation P3 strategic HOLD and create no Task.",
  "state_preservation" => "P3-001 credit and P3-002 through P3-007 terminal facts remain unchanged; P4 stays HOLD and the same long-term Goal stays ACTIVE.",
  "governing_artifact" => {
    "path" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_PATH,
    "byte_length" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_BYTES,
    "sha256" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PREINSTALL_TRUTH_SHA256
  },
  "validator_evidence" => evidence(
    disposition: "FOUNDER_RESERVED_DECISION_RESOLVED_P3_FINAL_TRANSACTIONAL_ROUTE_HOLD",
    decision: false,
    trigger: FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER,
    owner: "NONE"
  ),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_TOKEN,
    "requested_external_effect" => "MATERIAL_SCOPE"
  },
  "action_class" => "AUTHORIZATION_REQUIRED",
  "current_state" => "WAITING_USER",
  "material" => nil,
  "recommended_single_action" => "APPROVE_THE_EXACT_P3_HOST_AUTHORIZED_TRANSACTIONAL_REBASELINE",
  "copy_ready_text_or_exact_steps" => p3_host_authorized_body,
  "authorization" => {
    "authority_layer" => "FOUNDER_RESERVED",
    "reserved_trigger" => FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_PRIMARY_TRIGGER,
    "proposal_mode" => "CURRENT_RESOLVED_HOLD_REENTRY",
    "recommended_decision" => "APPROVE",
    "grant_scope" => {
      "operations" => p3_host_authorized_profile.fetch("operations"),
      "targets" => p3_host_authorized_profile.fetch("targets"),
      "duration" => p3_host_authorized_profile.fetch("duration"),
      "budget_or_external_effects" => p3_host_authorized_profile.fetch("budget_or_external_effects")
    },
    "risk_and_reversibility" => p3_host_authorized_risk,
    "deny_or_defer_effect" => p3_host_authorized_deny,
    "authorization_expiry_or_consumption_rule" => p3_host_authorized_profile.fetch("authorization_expiry_or_consumption_rule"),
    "pass_lifecycle" => p3_host_authorized_profile.fetch("pass_lifecycle"),
    "non_pass_lifecycle" => p3_host_authorized_profile.fetch("non_pass_lifecycle"),
    "operation_type" => "P3_MINIMUM_TRUST_HOST_AUTHORIZED_TRANSACTIONAL_BOUNDARY_OBJECTIVE_AND_ROUTE_REBASELINE_AFTER_P3_007"
  }
)
p3_host_authorized_draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: true
  RECOMMENDED_SINGLE_ACTION: #{p3_host_authorized["recommended_single_action"]}
  COPY_READY_TEXT_OR_EXACT_STEPS: #{p3_host_authorized_body}
  AGENT_CONTINUATION_AFTER_ACTION: #{p3_host_authorized["agent_continuation_after_action"]}
MARKDOWN
assert_pass!("P3 host-authorized transactional rebaseline exact body", p3_host_authorized,
             p3_host_authorized_draft, p3_host_authorized_truth)

drift_commit = "0" * 40
assert_reject!(
  "P3 host-authorized transactional rebaseline rejects canonical identity drift",
  p3_host_authorized.merge(
    "canonical_identity" => p3_host_authorized.fetch("canonical_identity").merge("commit" => drift_commit)
  ),
  p3_host_authorized_draft,
  p3_host_authorized_truth
)

old_p3_token = FounderActionHandoff::P3_ZERO_AUTHORITY_ROUTE_TOKEN
old_token_body = p3_host_authorized_body.sub(FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_TOKEN,
                                               old_p3_token)
assert_reject!(
  "P3 host-authorized transactional rebaseline rejects old P3 token",
  p3_host_authorized.merge("copy_ready_text_or_exact_steps" => old_token_body),
  p3_host_authorized_draft.sub(p3_host_authorized_body, old_token_body),
  p3_host_authorized_truth
)

expanded_budget = "将累计 P3 ceiling 精确扩为 11 engineering Tasks / 320 engineering hours / 80 calendar days；"
expanded_budget_body = p3_host_authorized_body.sub(
  FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_BUDGET, expanded_budget
)
expanded_budget_package = p3_host_authorized.merge(
  "copy_ready_text_or_exact_steps" => expanded_budget_body,
  "authorization" => p3_host_authorized.fetch("authorization").merge(
    "grant_scope" => p3_host_authorized.dig("authorization", "grant_scope").merge(
      "budget_or_external_effects" => expanded_budget
    )
  )
)
assert_reject!(
  "P3 host-authorized transactional rebaseline rejects expanded budget",
  expanded_budget_package,
  p3_host_authorized_draft.sub(p3_host_authorized_body, expanded_budget_body),
  p3_host_authorized_truth
)

weakened_exit_body = p3_host_authorized_body.sub(
  "P3 strict Exit Gate 精确保持 “Resume, isolation, permission and trace tests”；",
  "P3 strict Exit Gate 允许按 delivery milestone 部分通过；"
)
assert_reject!(
  "P3 host-authorized transactional rebaseline rejects weakened Exit Gate",
  p3_host_authorized.merge("copy_ready_text_or_exact_steps" => weakened_exit_body),
  p3_host_authorized_draft.sub(p3_host_authorized_body, weakened_exit_body),
  p3_host_authorized_truth
)

lineage_reuse_body = p3_host_authorized_body.sub(
  "永久冻结，不读取、不比较、不复制、不执行、不修复、不复用；",
  "允许读取并复用 rejected lineage；"
)
assert_reject!(
  "P3 host-authorized transactional rebaseline rejects rejected-lineage reuse",
  p3_host_authorized.merge("copy_ready_text_or_exact_steps" => lineage_reuse_body),
  p3_host_authorized_draft.sub(p3_host_authorized_body, lineage_reuse_body),
  p3_host_authorized_truth
)

automatic_p4_body = p3_host_authorized_body.sub(
  "不自动授权 P4。",
  "自动授权 P4。"
)
assert_reject!(
  "P3 host-authorized transactional rebaseline rejects automatic P4 entry",
  p3_host_authorized.merge("copy_ready_text_or_exact_steps" => automatic_p4_body),
  p3_host_authorized_draft.sub(p3_host_authorized_body, automatic_p4_body),
  p3_host_authorized_truth
)

assert_reject!(
  "P3 host-authorized transactional rebaseline rejects missing capacity trigger",
  p3_host_authorized.merge(
    "authorization" => p3_host_authorized.fetch("authorization").merge(
      "grant_scope" => p3_host_authorized.dig("authorization", "grant_scope").merge(
        "operations" => p3_host_authorized_profile.fetch("operations") - [
          FounderActionHandoff::P3_HOST_AUTHORIZED_ROUTE_CAPACITY_TRIGGER
        ]
      )
    )
  ),
  p3_host_authorized_draft,
  p3_host_authorized_truth
)

p3_hpe_truth = truth_bytes(
  disposition: "FOUNDER_RESERVED_DECISION_REQUIRED", decision: true,
  trigger: FounderActionHandoff::P3_HPE_ROUTE_PRIMARY_TRIGGER, owner: "HUMAN_FOUNDER"
)
p3_hpe_body = File.binread(
  "/Users/lijunpeng/.codex/attachments/e77ae6e2-1ec9-49dc-8853-f7ad62f9a76d/pasted-text.txt"
).force_encoding("UTF-8")
abort "P3 HPE Founder body fixture encoding invalid" unless p3_hpe_body.valid_encoding?
p3_hpe_body = p3_hpe_body.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
p3_hpe_profile = FounderActionHandoff::FOUNDER_NETWORK_OPERATION_PROFILES.fetch(
  FounderActionHandoff::P3_HPE_ROUTE_OPERATION_TYPE
)
p3_hpe_risk =
  "本授权不是对失败 Task 的重试、Candidate 3、successor、replacement、normalization、remediation 或历史 lineage 恢复；"
p3_hpe_deny =
  "禁止 network、DNS、AF_INET、AF_INET6、Provider、Secret、real-secret read、remote write、production、public release、existing-database mutation、write outside exact Task roots、irreversible deletion、开放 shell、任意 executable、任意环境继承或 P4 entry。"
p3_hpe = common.merge(
  "canonical_identity" => {
    "commit" => FounderActionHandoff::P3_HPE_ROUTE_PREINSTALL_COMMIT,
    "tree" => FounderActionHandoff::P3_HPE_ROUTE_PREINSTALL_TREE,
    "branch" => "main"
  },
  "truth_sha256" => Digest::SHA256.hexdigest(p3_hpe_truth),
  "basis" => {
    "facts" => ["The exact terminal TIK Route requires the Founder-authorized independent HPE rebaseline."],
    "inferences" => [],
    "unknowns" => []
  },
  "affected_scope" => "Only the exact three-stage P3 HPE Route and non-resettable cumulative envelope are changed.",
  "project_authorized" => "NO",
  "app_filesystem_approval_required" => "NO",
  "write_not_executed" => "YES",
  "agent_continuation_after_action" => "Install the exact HPE decision, Truth projection and existing-validator closed profile, then activate only Stage 1 after Stage 0 validation PASS.",
  "resume_condition" => "The exact direct Founder body and all bound preinstallation identities pass revalidation.",
  "safe_default" => "Preserve the terminal TIK state and create no HPE Task.",
  "state_preservation" => "P3-001 remains accepted, P4 remains HOLD, the project is incomplete and the long-term Goal remains ACTIVE.",
  "governing_artifact" => {
    "path" => FounderActionHandoff::P3_HPE_ROUTE_PREINSTALL_TRUTH_PATH,
    "byte_length" => FounderActionHandoff::P3_HPE_ROUTE_PREINSTALL_TRUTH_BYTES,
    "sha256" => FounderActionHandoff::P3_HPE_ROUTE_PREINSTALL_TRUTH_SHA256
  },
  "validator_evidence" => evidence(
    disposition: "FOUNDER_RESERVED_DECISION_REQUIRED", decision: true,
    trigger: FounderActionHandoff::P3_HPE_ROUTE_PRIMARY_TRIGGER, owner: "HUMAN_FOUNDER"
  ),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => FounderActionHandoff::P3_HPE_ROUTE_TOKEN,
    "requested_external_effect" => "MATERIAL_SCOPE"
  },
  "action_class" => "AUTHORIZATION_REQUIRED",
  "current_state" => "WAITING_USER",
  "material" => nil,
  "recommended_single_action" => "APPROVE_THE_EXACT_P3_HPE_REBASELINE",
  "copy_ready_text_or_exact_steps" => p3_hpe_body,
  "authorization" => {
    "authority_layer" => "FOUNDER_RESERVED",
    "reserved_trigger" => FounderActionHandoff::P3_HPE_ROUTE_PRIMARY_TRIGGER,
    "proposal_mode" => "CURRENT_CANONICAL_TRIGGER",
    "recommended_decision" => "APPROVE",
    "grant_scope" => {
      "operations" => p3_hpe_profile.fetch("operations"),
      "targets" => p3_hpe_profile.fetch("targets"),
      "duration" => p3_hpe_profile.fetch("duration"),
      "budget_or_external_effects" => p3_hpe_profile.fetch("budget_or_external_effects")
    },
    "risk_and_reversibility" => p3_hpe_risk,
    "deny_or_defer_effect" => p3_hpe_deny,
    "authorization_expiry_or_consumption_rule" =>
      p3_hpe_profile.fetch("authorization_expiry_or_consumption_rule"),
    "pass_lifecycle" => p3_hpe_profile.fetch("pass_lifecycle"),
    "non_pass_lifecycle" => p3_hpe_profile.fetch("non_pass_lifecycle"),
    "operation_type" => FounderActionHandoff::P3_HPE_ROUTE_OPERATION_TYPE
  }
)
p3_hpe_draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: true
  RECOMMENDED_SINGLE_ACTION: #{p3_hpe["recommended_single_action"]}
  COPY_READY_TEXT_OR_EXACT_STEPS: #{p3_hpe_body}
  AGENT_CONTINUATION_AFTER_ACTION: #{p3_hpe["agent_continuation_after_action"]}
MARKDOWN
assert_pass!("P3 HPE rebaseline exact body", p3_hpe, p3_hpe_draft, p3_hpe_truth)

p3_hpe_budget_drift = p3_hpe_body.sub(
  FounderActionHandoff::P3_HPE_ROUTE_BUDGET,
  "将 P3 累计 ceiling 精确改为 13 engineering Tasks / 336 engineering hours / 84 calendar days；"
)
assert_reject!(
  "P3 HPE rebaseline rejects expanded Task ceiling",
  p3_hpe.merge("copy_ready_text_or_exact_steps" => p3_hpe_budget_drift),
  p3_hpe_draft.sub(p3_hpe_body, p3_hpe_budget_drift),
  p3_hpe_truth
)

p3_hpe_lineage_drift = p3_hpe_body.sub(
  FounderActionHandoff::P3_HPE_ROUTE_LINEAGE,
  "允许读取和复用 rejected TIK engineering lineage。"
)
assert_reject!(
  "P3 HPE rebaseline rejects rejected-lineage reuse",
  p3_hpe.merge("copy_ready_text_or_exact_steps" => p3_hpe_lineage_drift),
  p3_hpe_draft.sub(p3_hpe_body, p3_hpe_lineage_drift),
  p3_hpe_truth
)

p3_mtro_truth = <<~YAML
  project: SourceLens
  current_phase: P3
  founder_escalation_control:
    schema_version: founder-escalation-control/v2
    disposition: FOUNDER_RESERVED_DECISION_REQUIRED
    source_event:
      kind: P3_TRIVS_F2_ROUTE_TERMINAL_NON_PASS
      status: P3_TRIVS_EVIDENCE_FIRST_FOUNDATION_ROUTE_TERMINAL_NON_PASS
    reserved_trigger:
      category: #{FounderActionHandoff::P3_MTRO_ROUTE_PRIMARY_TRIGGER}
      evidence:
        path: #{FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_PATH}
        byte_length: #{FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_BYTES}
        sha256: #{FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_SHA256}
    phase_gate_status: INCOMPLETE
    founder_decision_required: true
    next_action_owner: HUMAN_FOUNDER
    next_eligible_action: FOUNDER_DECIDE_P3_AFTER_TRIVS_F2_TERMINAL_NON_PASS
YAML
p3_mtro_body = File.binread(
  FounderActionHandoff::P3_MTRO_ROUTE_DIRECT_ATTACHMENT_PATH
).force_encoding("UTF-8")
abort "P3 MTRO Founder body fixture encoding invalid" unless p3_mtro_body.valid_encoding?
p3_mtro_body = p3_mtro_body.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
p3_mtro_profile = FounderActionHandoff::FOUNDER_NETWORK_OPERATION_PROFILES.fetch(
  FounderActionHandoff::P3_MTRO_ROUTE_OPERATION_TYPE
)
p3_mtro_terminal_handoff = {
  "terminal_level" => "ROUTE",
  "terminal_status" => "TERMINAL_TASK_GATE_NON_PASS",
  "receipt_path" => FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_PATH,
  "receipt_byte_length" => FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_BYTES,
  "receipt_sha256" => FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_SHA256,
  "no_automatic_successor_clause_present" => true,
  "no_automatic_successor_interpretation" =>
    FounderActionHandoff::TERMINAL_HANDOFF_INTERPRETATION,
  "next_step_user_action_required" => true,
  "copy_ready_handoff_required" => true,
  "copy_ready_handoff_suppressed" => false
}
p3_mtro = common.merge(
  "canonical_identity" => {
    "commit" => FounderActionHandoff::P3_MTRO_ROUTE_PREINSTALL_COMMIT,
    "tree" => FounderActionHandoff::P3_MTRO_ROUTE_PREINSTALL_TREE,
    "branch" => "main"
  },
  "truth_sha256" => Digest::SHA256.hexdigest(p3_mtro_truth),
  "basis" => {
    "facts" => [
      "The exact F2 acceptance protocol is terminal and mechanically unreachable before Product write.",
      "The direct Founder V2 body authorizes one final MTRO Product route without resetting capacity."
    ],
    "inferences" => [],
    "unknowns" => []
  },
  "affected_scope" =>
    "Only Strategic Constitution v3.6 and the exact one-Task P3 MTRO final Product Route.",
  "project_authorized" => "NO",
  "app_filesystem_approval_required" => "NO",
  "write_not_executed" => "YES",
  "agent_continuation_after_action" =>
    "Install v3.6, run the registered validators, activate only MTRO-P1, then begin the exact pre-write OCI probe.",
  "resume_condition" =>
    "The exact V2 body, canonical start, F2 terminal identity and closed MTRO profile all pass.",
  "safe_default" =>
    "Preserve the F2 terminal state and create no Product Task if any frozen identity drifts.",
  "state_preservation" =>
    "P3 remains 25 percent and strict Exit zero until Product acceptance; P4 stays HOLD and the Long-term Goal stays ACTIVE.",
  "governing_artifact" => {
    "path" => FounderActionHandoff::P3_MTRO_ROUTE_PREINSTALL_TRUTH_PATH,
    "byte_length" => FounderActionHandoff::P3_MTRO_ROUTE_PREINSTALL_TRUTH_BYTES,
    "sha256" => FounderActionHandoff::P3_MTRO_ROUTE_PREINSTALL_TRUTH_SHA256
  },
  "validator_evidence" => evidence(
    disposition: "FOUNDER_RESERVED_DECISION_REQUIRED", decision: true,
    trigger: FounderActionHandoff::P3_MTRO_ROUTE_PRIMARY_TRIGGER, owner: "HUMAN_FOUNDER"
  ),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => FounderActionHandoff::P3_MTRO_ROUTE_TOKEN,
    "requested_external_effect" => "MATERIAL_SCOPE"
  },
  "terminal_next_step_handoff" => p3_mtro_terminal_handoff,
  "action_class" => "AUTHORIZATION_REQUIRED",
  "current_state" => "WAITING_USER",
  "material" => nil,
  "recommended_single_action" => "APPROVE_THE_EXACT_P3_MTRO_FINAL_PRODUCT_ROUTE_V2",
  "copy_ready_text_or_exact_steps" => p3_mtro_body,
  "authorization" => {
    "authority_layer" => "FOUNDER_RESERVED",
    "reserved_trigger" => FounderActionHandoff::P3_MTRO_ROUTE_PRIMARY_TRIGGER,
    "proposal_mode" => "CURRENT_CANONICAL_TRIGGER",
    "recommended_decision" => "APPROVE",
    "grant_scope" => {
      "operations" => p3_mtro_profile.fetch("operations"),
      "targets" => p3_mtro_profile.fetch("targets"),
      "duration" => p3_mtro_profile.fetch("duration"),
      "budget_or_external_effects" => p3_mtro_profile.fetch("budget_or_external_effects")
    },
    "risk_and_reversibility" => p3_mtro_profile.fetch("risk_and_reversibility"),
    "deny_or_defer_effect" => p3_mtro_profile.fetch("deny_or_defer_effect"),
    "authorization_expiry_or_consumption_rule" =>
      p3_mtro_profile.fetch("authorization_expiry_or_consumption_rule"),
    "pass_lifecycle" => p3_mtro_profile.fetch("pass_lifecycle"),
    "non_pass_lifecycle" => p3_mtro_profile.fetch("non_pass_lifecycle"),
    "operation_type" => FounderActionHandoff::P3_MTRO_ROUTE_OPERATION_TYPE
  }
)
p3_mtro_draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: true
  RECOMMENDED_SINGLE_ACTION: #{p3_mtro["recommended_single_action"]}
  COPY_READY_TEXT_OR_EXACT_STEPS: #{p3_mtro_body}
  AGENT_CONTINUATION_AFTER_ACTION: #{p3_mtro["agent_continuation_after_action"]}
MARKDOWN
assert_pass!(
  "P3 MTRO final Product Route exact V2 body",
  p3_mtro, p3_mtro_draft, p3_mtro_truth,
  terminal_receipt_path: FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_PATH
)

p3_mtro_body_drift = p3_mtro_body.sub(
  "budget：1 Task、48 engineering hours、10 calendar days",
  "budget：2 Tasks、96 engineering hours、20 calendar days"
)
assert_reject!(
  "P3 MTRO final Product Route rejects body and budget drift",
  p3_mtro.merge("copy_ready_text_or_exact_steps" => p3_mtro_body_drift),
  p3_mtro_draft.sub(p3_mtro_body, p3_mtro_body_drift),
  p3_mtro_truth,
  terminal_receipt_path: FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_PATH
)

assert_reject!(
  "P3 MTRO final Product Route rejects old V1 token",
  p3_mtro.merge(
    "copy_ready_text_or_exact_steps" => p3_mtro_body.sub(
      FounderActionHandoff::P3_MTRO_ROUTE_TOKEN,
      FounderActionHandoff::P3_TRIVS_EVIDENCE_FIRST_ROUTE_TOKEN
    )
  ),
  p3_mtro_draft.sub(
    p3_mtro_body,
    p3_mtro_body.sub(
      FounderActionHandoff::P3_MTRO_ROUTE_TOKEN,
      FounderActionHandoff::P3_TRIVS_EVIDENCE_FIRST_ROUTE_TOKEN
    )
  ),
  p3_mtro_truth,
  terminal_receipt_path: FounderActionHandoff::P3_MTRO_ROUTE_F2_TERMINAL_RECEIPT_PATH
)

p3_iel_truth, p3_iel_truth_stderr, p3_iel_truth_status = Open3.capture3(
  "git", "-C", FounderActionHandoff::ROOT, "show",
  "#{FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_COMMIT}:#{FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TRUTH_PATH}"
)
abort "P3 IEL frozen preinstall Truth unavailable: #{p3_iel_truth_stderr.strip}" unless
  p3_iel_truth_status.success?
abort "P3 IEL frozen preinstall Truth exact identity drift" unless
  p3_iel_truth.bytesize == FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TRUTH_BYTES &&
  Digest::SHA256.hexdigest(p3_iel_truth) ==
    FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TRUTH_SHA256
p3_iel_truth_record = YAML.safe_load(
  p3_iel_truth, permitted_classes: [], permitted_symbols: [], aliases: false
)
p3_iel_body = File.binread(
  FounderActionHandoff::P3_IEL_ROUTE_DIRECT_ATTACHMENT_PATH
).force_encoding("UTF-8")
abort "P3 IEL direct Founder body fixture encoding invalid" unless p3_iel_body.valid_encoding?
abort "P3 IEL direct Founder body fixture identity drift" unless
  p3_iel_body.bytesize == FounderActionHandoff::P3_IEL_ROUTE_DIRECT_ATTACHMENT_BYTES &&
  Digest::SHA256.hexdigest(p3_iel_body.b) ==
    FounderActionHandoff::P3_IEL_ROUTE_DIRECT_ATTACHMENT_SHA256 &&
  p3_iel_body.lines.first.chomp == FounderActionHandoff::P3_IEL_ROUTE_TOKEN
p3_iel_profile = FounderActionHandoff::FOUNDER_NETWORK_OPERATION_PROFILES.fetch(
  FounderActionHandoff::P3_IEL_ROUTE_OPERATION_TYPE
)
p3_iel = common.merge(
  "canonical_identity" => {
    "commit" => FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_COMMIT,
    "tree" => FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TREE,
    "branch" => "main"
  },
  "truth_sha256" => Digest::SHA256.hexdigest(p3_iel_truth),
  "basis" => {
    "facts" => [
      "The exact EGT Product Route is terminal with no current Founder trigger projection.",
      "The direct Founder body authorizes one strategic IEL rebaseline under two reserved categories."
    ],
    "inferences" => [],
    "unknowns" => []
  },
  "affected_scope" =>
    "Only the exact P3 IEL Objective, strict Exit Gate, strategic installation and three-stage completion Route.",
  "project_authorized" => "NO",
  "app_filesystem_approval_required" => "NO",
  "write_not_executed" => "YES",
  "agent_continuation_after_action" =>
    "Install the create-once IEL decision, typed validators, Constitution v4.0 and consistent Truth projections, then activate only F1.",
  "resume_condition" =>
    "The exact direct Founder body, frozen canonical identities, two triggers and closed IEL profile all pass.",
  "safe_default" =>
    "Preserve the frozen EGT terminal state and create no IEL Task if any identity, scope or lifecycle drifts.",
  "state_preservation" =>
    "P3 stays at management 25 percent and strict zero during installation; P4 stays HOLD and the Long-term Goal stays ACTIVE.",
  "governing_artifact" => {
    "path" => FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TRUTH_PATH,
    "byte_length" => FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TRUTH_BYTES,
    "sha256" => FounderActionHandoff::P3_IEL_ROUTE_PREINSTALL_TRUTH_SHA256
  },
  "validator_evidence" => evidence(
    disposition: "NO_RESERVED_TRIGGER_ROUTE_TERMINAL", decision: false,
    trigger: "NONE", owner: "NONE"
  ),
  "user_request_evidence" => {
    "source" => "CURRENT_DIRECT_USER_MESSAGE",
    "exact_token" => FounderActionHandoff::P3_IEL_ROUTE_TOKEN,
    "requested_external_effect" => "MATERIAL_SCOPE"
  },
  "terminal_next_step_handoff" => nil,
  "action_class" => "AUTHORIZATION_REQUIRED",
  "current_state" => "WAITING_USER",
  "material" => nil,
  "recommended_single_action" => "APPROVE_THE_EXACT_P3_IEL_COMPLETION_ROUTE_V1",
  "copy_ready_text_or_exact_steps" => p3_iel_body,
  "authorization" => {
    "authority_layer" => "FOUNDER_RESERVED",
    "reserved_trigger" => FounderActionHandoff::P3_IEL_ROUTE_PRIMARY_TRIGGER,
    "proposal_mode" => "CURRENT_CANONICAL_TRIGGER",
    "recommended_decision" => "APPROVE",
    "grant_scope" => {
      "operations" => p3_iel_profile.fetch("operations"),
      "targets" => p3_iel_profile.fetch("targets"),
      "duration" => p3_iel_profile.fetch("duration"),
      "budget_or_external_effects" => p3_iel_profile.fetch("budget_or_external_effects")
    },
    "risk_and_reversibility" => p3_iel_profile.fetch("risk_and_reversibility"),
    "deny_or_defer_effect" => p3_iel_profile.fetch("deny_or_defer_effect"),
    "authorization_expiry_or_consumption_rule" =>
      p3_iel_profile.fetch("authorization_expiry_or_consumption_rule"),
    "pass_lifecycle" => p3_iel_profile.fetch("pass_lifecycle"),
    "non_pass_lifecycle" => p3_iel_profile.fetch("non_pass_lifecycle"),
    "operation_type" => FounderActionHandoff::P3_IEL_ROUTE_OPERATION_TYPE
  }
)
p3_iel_draft = <<~MARKDOWN
  USER_ACTION_REQUIRED: true
  RECOMMENDED_SINGLE_ACTION: #{p3_iel["recommended_single_action"]}
  COPY_READY_TEXT_OR_EXACT_STEPS: #{p3_iel_body}
  AGENT_CONTINUATION_AFTER_ACTION: #{p3_iel["agent_continuation_after_action"]}
MARKDOWN
deep_copy = ->(value) { Marshal.load(Marshal.dump(value)) }
assert_pass!("P3 IEL exact frozen Truth and direct Founder body", p3_iel, p3_iel_draft,
             p3_iel_truth)

stale_iel_identity = deep_copy.call(p3_iel)
stale_iel_identity["canonical_identity"]["commit"] = "0" * 40
assert_reject!("P3 IEL rejects stale commit identity", stale_iel_identity, p3_iel_draft,
               p3_iel_truth)

stale_iel_truth_identity = deep_copy.call(p3_iel)
stale_iel_truth_identity["governing_artifact"]["sha256"] = "0" * 64
assert_reject!("P3 IEL rejects stale Truth identity", stale_iel_truth_identity, p3_iel_draft,
               p3_iel_truth)

wrong_iel_operation = deep_copy.call(p3_iel)
wrong_iel_operation["authorization"]["operation_type"] =
  FounderActionHandoff::P3_MTRO_ROUTE_OPERATION_TYPE
assert_reject!("P3 IEL rejects wrong operation type", wrong_iel_operation, p3_iel_draft,
               p3_iel_truth)

missing_iel_strategy_trigger = deep_copy.call(p3_iel)
missing_iel_strategy_trigger["authorization"]["reserved_trigger"] =
  FounderActionHandoff::P3_IEL_ROUTE_CAPACITY_TRIGGER
assert_reject!("P3 IEL rejects missing strategy trigger", missing_iel_strategy_trigger,
               p3_iel_draft, p3_iel_truth)

ordinary_non_pass = deep_copy.call(p3_iel_truth_record)
ordinary_non_pass["founder_escalation_control"]["source_event"]["kind"] =
  "ORDINARY_TASK_IMPLEMENTATION_NON_PASS"
ordinary_non_pass_bytes = YAML.dump(ordinary_non_pass)
ordinary_non_pass_package = deep_copy.call(p3_iel)
ordinary_non_pass_package["truth_sha256"] = Digest::SHA256.hexdigest(ordinary_non_pass_bytes)
assert_reject!("P3 IEL rejects ordinary NON_PASS masquerade", ordinary_non_pass_package,
               p3_iel_draft, ordinary_non_pass_bytes)

early_p4 = deep_copy.call(p3_iel_truth_record)
early_p4["project"]["p4_entry_status"] = "ACTIVE"
early_p4["strict_phase_gate_ledger"]["phases"]["P4"]["entry_authorized"] = true
early_p4_bytes = YAML.dump(early_p4)
early_p4_package = deep_copy.call(p3_iel)
early_p4_package["truth_sha256"] = Digest::SHA256.hexdigest(early_p4_bytes)
assert_reject!("P3 IEL rejects early P4 entry", early_p4_package, p3_iel_draft,
               early_p4_bytes)

closed_goal = deep_copy.call(p3_iel_truth_record)
closed_goal["goal"]["long_term_goal_status"] = "COMPLETE"
closed_goal["goal"]["codex_goal_action"] = "COMPLETE"
closed_goal_bytes = YAML.dump(closed_goal)
closed_goal_package = deep_copy.call(p3_iel)
closed_goal_package["truth_sha256"] = Digest::SHA256.hexdigest(closed_goal_bytes)
assert_reject!("P3 IEL rejects Long-term Goal closure", closed_goal_package, p3_iel_draft,
               closed_goal_bytes)

stale_egt_activation = deep_copy.call(p3_iel_truth_record)
stale_egt_activation["active_work"]["selected_task"] = "AIOS-P3-EGT-P1_STRICT_CAPABILITY_CLEAN_ROOM_PRODUCT"
stale_egt_activation["active_work"]["next_eligible_action"] = "MASTER_ACTIVATE_AIOS_P3_EGT_P1"
stale_egt_bytes = YAML.dump(stale_egt_activation)
stale_egt_package = deep_copy.call(p3_iel)
stale_egt_package["truth_sha256"] = Digest::SHA256.hexdigest(stale_egt_bytes)
assert_reject!("P3 IEL rejects stale EGT activation", stale_egt_package, p3_iel_draft,
               stale_egt_bytes)

{
  "overbudget" => ["3 engineering Tasks", "4 engineering Tasks"],
  "rejected lineage read permission" => [
    "clean-room access audit发现任何rejected lineage read时，本路线立即NON_PASS；",
    "clean-room access audit发现rejected lineage read时仍允许继续；"
  ],
  "Candidate 3" => ["Candidate 3", "Candidate 3 allowed"],
  "second repair" => ["第二次same-Task repair", "第二次same-Task repair allowed"],
  "third review" => ["第三次review cycle", "第三次review cycle allowed"],
  "second formal" => ["第二次formal dispatch", "第二次formal dispatch allowed"],
  "rerun-to-pass" => ["rerun-to-pass", "rerun-to-pass allowed"]
}.each do |label, (from, to)|
  mutated_body = p3_iel_body.sub(from, to)
  abort "P3 IEL #{label} mutation fixture did not change the body" if mutated_body == p3_iel_body
  mutated_package = deep_copy.call(p3_iel)
  mutated_package["copy_ready_text_or_exact_steps"] = mutated_body
  mutated_draft = p3_iel_draft.sub(p3_iel_body, mutated_body)
  assert_reject!("P3 IEL rejects #{label}", mutated_package, mutated_draft, p3_iel_truth)
end

assert_reject!(
  "P3 IEL rejects newline-normalized authority body",
  p3_iel.merge("copy_ready_text_or_exact_steps" => p3_iel_body + "\n"),
  p3_iel_draft.sub(p3_iel_body, p3_iel_body + "\n"),
  p3_iel_truth
)

ASSERTIONS[:count] += 1
abort "P3 MTRO operation type is not founder-authorized closed schema" unless
  FounderActionHandoff::FOUNDER_OPERATION_TYPES.include?(
    FounderActionHandoff::P3_MTRO_ROUTE_OPERATION_TYPE
  )

ASSERTIONS[:count] += 1
abort "P3 DTK operation type is not founder-authorized closed schema" unless
  FounderActionHandoff::FOUNDER_OPERATION_TYPES.include?(
    FounderActionHandoff::P3_DTK_ROUTE_OPERATION_TYPE
  )

ASSERTIONS[:count] += 1
dtk_profile = FounderActionHandoff::P3_DTK_ROUTE_PROFILE
abort "P3 DTK profile token or frozen findings drift" unless
  dtk_profile.fetch("token") == FounderActionHandoff::P3_DTK_ROUTE_TOKEN &&
  %w[P3-ETSK-F1-C1-P0-001 P3-ETSK-F1-C1-P1-002 P3-ETSK-F1-C1-P1-003].all? { |id|
    dtk_profile.fetch("operations").any? { |operation| operation.include?(id) }
  }

ASSERTIONS[:count] += 1
abort "P3 DTK profile budget, lineage or external-effect boundary drift" unless
  dtk_profile.fetch("budget_or_external_effects").include?("17 Tasks / 464 hours / 110 days") &&
  dtk_profile.fetch("operations").any? { |operation| operation.include?("禁止读取、比较、复制、执行、恢复、修复或复用") } &&
  dtk_profile.fetch("operations").any? { |operation| operation.include?("Foundation 禁止 Docker") }

puts "FOUNDER_ACTION_HANDOFF_TESTS: PASS assertions=#{ASSERTIONS[:count]}"

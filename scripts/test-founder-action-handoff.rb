#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
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

def assert_pass!(label, package, draft, truth_bytes, user_token: package.dig("user_request_evidence", "exact_token"))
  ASSERTIONS[:count] += 1
  write_fixture(JSON.generate(package) + "\n", draft, truth_bytes) do |truth, package_path, draft_path|
    FounderActionHandoff.validate!(
      truth_path: truth, package_path: package_path, draft_path: draft_path, test_fixture: true,
      current_user_request_token: user_token
    )
  end
rescue StandardError => error
  abort "#{label}: expected PASS, got #{error.class}: #{error.message}"
end

def assert_reject!(label, package, draft, truth_bytes, user_token: package.dig("user_request_evidence", "exact_token"))
  assert_raw_reject!(label, JSON.generate(package) + "\n", draft, truth_bytes, user_token: user_token)
end

def assert_raw_reject!(label, package_bytes, draft, truth_bytes, user_token: nil)
  ASSERTIONS[:count] += 1
  write_fixture(package_bytes, draft, truth_bytes) do |truth, package_path, draft_path|
    begin
      FounderActionHandoff.validate!(
        truth_path: truth, package_path: package_path, draft_path: draft_path, test_fixture: true,
        current_user_request_token: user_token
      )
    rescue FounderActionHandoff::ValidationError, KeyError, TypeError
      next
    end
    abort "#{label}: expected NON_PASS, got PASS"
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

def prospective_preflight
  policy = identity("docs/aios/FOUNDER_DELEGATION_POLICY.md")
  {
    "status" => "PASS",
    "capability_gap" => FounderActionHandoff::PROSPECTIVE_PREFLIGHT,
    "current_disposition" => "NO_RESERVED_TRIGGER_CONTINUE_PHASE",
    "current_trigger" => "NONE",
    "requested_trigger" => "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT",
    "exact_external_effect" => "NETWORK",
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
  "user_request_evidence" => nil
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

standard_operation = FounderActionHandoff::STANDARD_CURL_OPERATION
standard_budget = FounderActionHandoff::STANDARD_CURL_BUDGET
standard_exclusions = FounderActionHandoff::STANDARD_CURL_METRIC_EXCLUSIONS
standard_retry = FounderActionHandoff::STANDARD_CURL_RETRY_POLICY
standard_curl_binding = FounderActionHandoff::STANDARD_CURL_IDENTITY_BINDING
standard_copy_text = <<~TEXT.strip
  AUTHORIZE_EXACT_BOUNDED_STANDARD_CURL_NETWORK_V1；canonical commit #{canonical['commit']}；tree #{canonical['tree']}；governing artifact #{plan['path']} #{plan['byte_length']} bytes SHA-256 #{plan['sha256']}；trigger #{trigger}；operation type READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL；operation #{standard_operation}；method #{method}；metric exclusions #{standard_exclusions}；retry policy #{standard_retry}；curl binding #{standard_curl_binding}；target #{target}；duration #{duration}；budget #{standard_budget}；risk #{risk}；deny #{denial}；expiry #{expiry}；PASS #{pass_lifecycle}；NON_PASS #{non_pass_lifecycle}
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

puts "FOUNDER_ACTION_HANDOFF_TESTS: PASS assertions=#{ASSERTIONS[:count]}"

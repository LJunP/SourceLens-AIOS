#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "open3"
require "optparse"
require "pathname"
require "yaml"

module FounderActionHandoff
  ROOT = File.expand_path("..", __dir__)
  DEFAULT_TRUTH = File.join(ROOT, "docs/aios/truth/project_state.yaml")
  RECOVERY_PLAN = "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml"
  SCHEMA_VERSION = "user-action-handoff/v1"
  ACTION_CLASSES = %w[NONE_CONTINUE AUTHORIZATION_REQUIRED MATERIAL_REQUIRED].freeze
  CURRENT_STATES = %w[COMPLETE CONTINUING WAITING_USER].freeze
  FOUNDER_TRIGGERS = %w[
    PHASE_ENTRY_OR_EXIT
    MISSION_ICP_YEAR_ONE_OR_PHASE_ROUTE_CHANGE
    MATERIAL_SCOPE_BUDGET_OR_PERMISSION_EXPANSION_BEYOND_PHASE_ENVELOPE
    NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT
    IRREVERSIBLE_ASSET_REMOVAL
    MATERIAL_LEGAL_PRIVACY_OR_COMMERCIAL_COMMITMENT
    CRITICAL_RESIDUAL_RISK_ACCEPTANCE
  ].freeze
  PROJECT_AUTHORIZATION_VALUES = %w[YES NO NOT_APPLICABLE UNKNOWN].freeze
  APP_APPROVAL_VALUES = %w[YES NO UNKNOWN].freeze
  WRITE_VALUES = %w[YES NO NOT_APPLICABLE].freeze
  RECOMMENDED_DECISIONS = %w[APPROVE DENY DEFER].freeze
  FOUNDER_OPERATION_TYPES = %w[
    READ_ONLY_HTTPS_ACQUISITION
    READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL
  ].freeze
  APP_OPERATION_TYPES = %w[APP_FILESYSTEM_BATCH_WRITE].freeze
  READ_ONLY_HTTPS_OPERATION = "一次全新、独立、clean-room V6 benchmark source acquisition"
  READ_ONLY_HTTPS_METHOD = "仅允许无凭据 HTTPS GET/HEAD"
  READ_ONLY_HTTPS_TARGETS = "github.com、api.github.com、codeload.github.com、raw.githubusercontent.com、repo.maven.apache.org、downloads.gradle.org、plugins.gradle.org、plugins-artifacts.gradle.org"
  READ_ONLY_HTTPS_BUDGET = "4,294,967,296 PROCESS_DELIVERED_TCP_STREAM_OCTETS"
  STANDARD_CURL_OPERATION_PATTERN = /\A一次全新、独立、clean-room (V[1-9][0-9]*) benchmark source acquisition using exact system curl\z/
  STANDARD_CURL_BUDGET = "4,294,967,296 CREATE_ONCE_PERSISTED_HTTP_RESPONSE_BODY_OCTETS"
  STANDARD_CURL_METRIC_EXCLUSIONS = "This budget does not cap or claim DNS, TLS, HTTP header, kernel, wire, or raw TCP octets"
  STANDARD_CURL_RETRY_POLICY = "Retries are disabled"
  STANDARD_CURL_IDENTITY_BINDING = "Exact system curl identity must be bound before the first network request"
  FOUNDER_NETWORK_OPERATION_PROFILES = {
    "READ_ONLY_HTTPS_ACQUISITION" => {
      "operations" => [READ_ONLY_HTTPS_OPERATION, READ_ONLY_HTTPS_METHOD],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => READ_ONLY_HTTPS_BUDGET
    },
    "READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL" => {
      "operation_tail" => [
        READ_ONLY_HTTPS_METHOD,
        STANDARD_CURL_METRIC_EXCLUSIONS,
        STANDARD_CURL_RETRY_POLICY,
        STANDARD_CURL_IDENTITY_BINDING
      ],
      "targets" => [READ_ONLY_HTTPS_TARGETS],
      "budget_or_external_effects" => STANDARD_CURL_BUDGET
    }
  }.freeze
  PROSPECTIVE_PREFLIGHT = "PROSPECTIVE_RESERVED_EFFECT_REQUIRED_BY_EXACT_USER_REQUEST_AND_NOT_EXPRESSIBLE_BY_CURRENT_OFFLINE_ESCALATION_PROJECTION"
  NO_ACTION_SENTENCE = "你现在无需操作，我将在现有授权范围内继续执行。"
  PLACEHOLDER = /(TBD|TODO|待补|待定|PLACEHOLDER|\{[^}]+\}|<[^>]+>)/i
  FOUNDER_AUTHORIZATION_TOKEN = /(?<![A-Za-z0-9_])AUTHORIZE_[A-Z0-9_]+(?![A-Za-z0-9_])/
  MARKERS = %w[USER_ACTION_REQUIRED RECOMMENDED_SINGLE_ACTION COPY_READY_TEXT_OR_EXACT_STEPS AGENT_CONTINUATION_AFTER_ACTION].freeze
  SHA256 = /\A[0-9a-f]{64}\z/
  COMMIT = /\A[0-9a-f]{40}\z/

  class ValidationError < StandardError; end
  class DuplicateJsonKeyError < StandardError; end

  class DuplicateRejectingHash < Hash
    def []=(key, value)
      raise DuplicateJsonKeyError, "duplicate JSON key: #{key}" if key?(key)

      super
    end
  end

  module_function

  def assert!(condition, message)
    raise ValidationError, message unless condition
  end

  def exact_object!(value, keys, label)
    assert!(value.is_a?(Hash), "#{label} must be an object")
    assert!(value.keys.sort == keys.sort, "#{label} must be a closed object")
    value
  end

  def nonempty_string!(value, label)
    assert!(value.is_a?(String) && !value.strip.empty?, "#{label} must be a non-empty string")
    assert!(!value.match?(PLACEHOLDER), "#{label} contains a placeholder")
    value
  end

  def nonempty_strings!(value, label)
    assert!(value.is_a?(Array) && !value.empty?, "#{label} must be a non-empty array")
    value.each_with_index { |entry, index| nonempty_string!(entry, "#{label}[#{index}]") }
    value
  end

  def read_regular!(path, label)
    candidate = Pathname.new(path)
    flags = File::RDONLY
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(candidate, flags) do |file|
      stat = file.stat
      assert!(stat.file? && stat.nlink == 1, "#{label} must be regular nlink1")
      file.binmode
      file.read
    end
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "#{label} unavailable: #{error.message}"
  end

  def parse_json!(bytes, label)
    value = JSON.parse(bytes, object_class: DuplicateRejectingHash)
    assert!(value.is_a?(Hash), "#{label} must be a JSON object")
    value
  rescue JSON::ParserError, DuplicateJsonKeyError => error
    raise ValidationError, "#{label} JSON invalid: #{error.message}"
  end

  def canonical_truth_path
    Pathname.new(DEFAULT_TRUTH).realpath
  end

  def validate_truth_path!(truth_path)
    candidate = Pathname.new(truth_path)
    assert!(candidate.exist? && !candidate.symlink? && candidate.realpath == canonical_truth_path,
            "handoff check requires the canonical Truth path")
  end

  def git_output!(*args)
    output, error, status = Open3.capture3("git", "-C", ROOT, *args)
    assert!(status.success?, "Git identity lookup failed: #{error.strip}")
    output.strip
  end

  def current_git_identity
    {
      "commit" => git_output!("rev-parse", "HEAD"),
      "tree" => git_output!("rev-parse", "HEAD^{tree}"),
      "branch" => git_output!("branch", "--show-current")
    }
  end

  def validate_common!(package, truth_bytes)
    exact_object!(package, %w[
      schema_version action_class truth_sha256 current_state basis affected_scope
      project_authorized app_filesystem_approval_required write_not_executed
      recommended_single_action copy_ready_text_or_exact_steps
      agent_continuation_after_action resume_condition safe_default state_preservation
      canonical_identity governing_artifact validator_evidence user_request_evidence authorization material
    ], "handoff package")
    assert!(package["schema_version"] == SCHEMA_VERSION, "handoff schema version mismatch")
    assert!(ACTION_CLASSES.include?(package["action_class"]), "handoff action class invalid")
    assert!(CURRENT_STATES.include?(package["current_state"]), "handoff current state invalid")
    assert!(package["truth_sha256"] == Digest::SHA256.hexdigest(truth_bytes), "handoff Truth SHA-256 mismatch")
    basis = exact_object!(package["basis"], %w[facts inferences unknowns], "handoff basis")
    nonempty_strings!(basis["facts"], "handoff facts")
    %w[inferences unknowns].each do |key|
      assert!(basis[key].is_a?(Array), "handoff #{key} must be an array")
      basis[key].each_with_index { |entry, index| nonempty_string!(entry, "handoff #{key}[#{index}]") }
    end
    %w[affected_scope agent_continuation_after_action resume_condition safe_default state_preservation].each do |key|
      nonempty_string!(package[key], "handoff #{key}")
    end
    assert!(PROJECT_AUTHORIZATION_VALUES.include?(package["project_authorized"]), "project authorization value invalid")
    assert!(APP_APPROVAL_VALUES.include?(package["app_filesystem_approval_required"]), "app approval value invalid")
    assert!(WRITE_VALUES.include?(package["write_not_executed"]), "write-not-executed value invalid")

    identity = exact_object!(package["canonical_identity"], %w[commit tree branch], "canonical identity")
    assert!(identity["commit"].is_a?(String) && identity["commit"].match?(COMMIT), "canonical commit invalid")
    assert!(identity["tree"].is_a?(String) && identity["tree"].match?(COMMIT), "canonical tree invalid")
    nonempty_string!(identity["branch"], "canonical branch")
    assert!(identity == current_git_identity, "handoff canonical Git identity drift")

    artifact = exact_object!(package["governing_artifact"], %w[path byte_length sha256], "governing artifact")
    nonempty_string!(artifact["path"], "governing artifact path")
    assert!(artifact["byte_length"].is_a?(Integer) && artifact["byte_length"].positive?, "governing artifact byte length invalid")
    assert!(artifact["sha256"].is_a?(String) && artifact["sha256"].match?(SHA256), "governing artifact SHA-256 invalid")
    artifact_path = Pathname.new(ROOT).join(artifact["path"]).cleanpath
    assert!(artifact_path.to_s.start_with?(ROOT + File::SEPARATOR), "governing artifact escaped repository")
    artifact_bytes = read_regular!(artifact_path, "governing artifact")
    assert!(artifact["byte_length"] == artifact_bytes.bytesize &&
            artifact["sha256"] == Digest::SHA256.hexdigest(artifact_bytes), "governing artifact identity drift")

    request = package["user_request_evidence"]
    if request
      exact_object!(request, %w[source exact_token requested_external_effect], "user request evidence")
      assert!(request["source"] == "CURRENT_DIRECT_USER_MESSAGE" &&
              request["requested_external_effect"] == "NETWORK",
              "direct user request binding invalid")
      nonempty_string!(request["exact_token"], "direct user request token")
    end

    evidence = exact_object!(package["validator_evidence"], %w[
      validator command expected_disposition expected_founder_decision_required expected_trigger
      expected_next_action_owner prospective_preflight
    ], "validator evidence")
    assert!(evidence["validator"] == "scripts/validate-founder-delegation-continuity.rb", "validator identity invalid")
    assert!(evidence["command"] == "ruby scripts/validate-founder-delegation-continuity.rb", "validator command invalid")
    nonempty_string!(evidence["expected_disposition"], "expected validator disposition")
    assert!([true, false].include?(evidence["expected_founder_decision_required"]), "expected Founder decision flag invalid")
    nonempty_string!(evidence["expected_trigger"], "expected validator trigger")
    nonempty_string!(evidence["expected_next_action_owner"], "expected validator next owner")
    if evidence["prospective_preflight"]
      preflight = exact_object!(evidence["prospective_preflight"], %w[
        status capability_gap current_disposition current_trigger requested_trigger
        exact_external_effect policy_path policy_byte_length policy_sha256
        ordinary_task_failure_is_not_trigger
      ], "prospective preflight")
      assert!(preflight["status"] == "PASS" && preflight["capability_gap"] == PROSPECTIVE_PREFLIGHT,
              "prospective preflight status invalid")
      assert!(preflight["current_disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
              preflight["current_trigger"] == "NONE" &&
              preflight["requested_trigger"] == "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT" &&
              preflight["exact_external_effect"] == "NETWORK" &&
              preflight["ordinary_task_failure_is_not_trigger"] == true,
              "prospective preflight scope invalid")
      assert!(preflight["policy_path"] == "docs/aios/FOUNDER_DELEGATION_POLICY.md",
              "prospective preflight policy path invalid")
      policy_path = Pathname.new(ROOT).join(preflight["policy_path"])
      policy_bytes = read_regular!(policy_path, "Founder delegation policy")
      assert!(preflight["policy_byte_length"] == policy_bytes.bytesize &&
              preflight["policy_sha256"] == Digest::SHA256.hexdigest(policy_bytes),
              "prospective preflight policy identity drift")
      assert!(policy_bytes.include?(preflight["requested_trigger"]) && policy_bytes.match?(/network/i),
              "Founder policy does not bind the prospective network effect")
    end
  end

  def validate_control!(truth, evidence, run_validator:)
    control = exact_object!(truth["founder_escalation_control"], %w[
      schema_version disposition source_event reserved_trigger phase_gate_status
      founder_decision_required next_action_owner next_eligible_action
    ], "canonical Founder escalation control")
    trigger = exact_object!(control["reserved_trigger"], %w[category evidence], "canonical reserved trigger")
    assert!(control["disposition"] == evidence["expected_disposition"], "validator disposition projection drift")
    assert!(control["founder_decision_required"] == evidence["expected_founder_decision_required"], "Founder decision projection drift")
    assert!(trigger["category"] == evidence["expected_trigger"], "Founder trigger projection drift")
    assert!(control["next_action_owner"] == evidence["expected_next_action_owner"], "Founder next-owner projection drift")
    if run_validator
      output, error, status = Open3.capture3("ruby", File.join(ROOT, evidence["validator"]))
      assert!(status.success?, "applicable Founder escalation validator NON_PASS: #{error.strip}")
      assert!(output.include?("disposition=#{control['disposition']}"), "Founder validator output does not bind current disposition")
    end
    control
  end

  def validate_authorization!(package, truth, control, current_user_request_token)
    authorization = exact_object!(package["authorization"], %w[
      authority_layer reserved_trigger proposal_mode recommended_decision grant_scope
      risk_and_reversibility deny_or_defer_effect authorization_expiry_or_consumption_rule
      pass_lifecycle non_pass_lifecycle operation_type
    ], "authorization handoff")
    assert!(%w[FOUNDER_RESERVED APP_FILESYSTEM].include?(authorization["authority_layer"]), "authority layer invalid")
    assert!(%w[CURRENT_CANONICAL_TRIGGER PROSPECTIVE_RESERVED_EFFECT NOT_APPLICABLE].include?(authorization["proposal_mode"]), "authorization proposal mode invalid")
    assert!(RECOMMENDED_DECISIONS.include?(authorization["recommended_decision"]), "recommended decision invalid")
    grant = exact_object!(authorization["grant_scope"], %w[operations targets duration budget_or_external_effects], "authorization grant scope")
    %w[operations targets].each { |key| nonempty_strings!(grant[key], "authorization #{key}") }
    %w[duration budget_or_external_effects].each { |key| nonempty_string!(grant[key], "authorization #{key}") }
    %w[risk_and_reversibility deny_or_defer_effect authorization_expiry_or_consumption_rule pass_lifecycle non_pass_lifecycle].each do |key|
      nonempty_string!(authorization[key], "authorization #{key}")
    end

    evidence = package["validator_evidence"]
    if authorization["authority_layer"] == "FOUNDER_RESERVED"
      assert!(FOUNDER_TRIGGERS.include?(authorization["reserved_trigger"]), "Founder reserved trigger invalid")
      assert!(authorization["proposal_mode"] != "NOT_APPLICABLE", "Founder proposal mode invalid")
      assert!(package["project_authorized"] == "NO" && package["app_filesystem_approval_required"] == "NO",
              "Founder request mixed project and App approval layers")
      if authorization["proposal_mode"] == "CURRENT_CANONICAL_TRIGGER"
        assert!(control["disposition"] == "FOUNDER_DECISION_REQUIRED" &&
                control["founder_decision_required"] == true &&
                control.dig("reserved_trigger", "category") == authorization["reserved_trigger"] &&
                evidence["prospective_preflight"].nil?,
                "Founder package does not match the current canonical trigger")
      else
        assert!(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
                control["founder_decision_required"] == false &&
                control.dig("reserved_trigger", "category") == "NONE" &&
                control["next_action_owner"] == "MASTER_CEO_AGENT",
                "prospective Founder package requires the exact current offline continue state")
        assert!(evidence["prospective_preflight"].is_a?(Hash) &&
                evidence["prospective_preflight"]["status"] == "PASS" &&
                evidence["prospective_preflight"]["capability_gap"] == PROSPECTIVE_PREFLIGHT,
                "prospective Founder request lacks the structured capability-gap preflight")
        request = package["user_request_evidence"]
        assert!(request.is_a?(Hash) && current_user_request_token.is_a?(String) &&
                !current_user_request_token.empty? &&
                request["source"] == "CURRENT_DIRECT_USER_MESSAGE" &&
                request["exact_token"] == current_user_request_token &&
                request["requested_external_effect"] == "NETWORK",
                "prospective Founder request lacks the independently supplied direct-user request binding")
        assert!(authorization["reserved_trigger"] == "NETWORK_PROVIDER_SECRET_REMOTE_PRODUCTION_OR_PUBLIC_EFFECT",
                "prospective request may only cover an exact external-effect Founder trigger")
      end
      assert!(FOUNDER_OPERATION_TYPES.include?(authorization["operation_type"]), "Founder operation type invalid")
      operation_type = authorization["operation_type"]
      profile = FOUNDER_NETWORK_OPERATION_PROFILES[operation_type]
      assert!(profile, "Founder network operation is not bound to a closed profile")
      if operation_type == "READ_ONLY_HTTPS_ACQUISITION_STANDARD_CURL"
        operations = grant["operations"]
        match = operations.is_a?(Array) && operations.first.is_a?(String) &&
                STANDARD_CURL_OPERATION_PATTERN.match(operations.first)
        assert!(match && operations.drop(1) == profile["operation_tail"],
                "standard-curl operation is not bound to one exact acquisition version")
        acquisition_version = match[1]
        proposed_tokens = package["copy_ready_text_or_exact_steps"].scan(FOUNDER_AUTHORIZATION_TOKEN)
        assert!(proposed_tokens.length == 1, "standard-curl handoff must contain one proposed authorization token")
        token_match = /\AAUTHORIZE_P2_BENCHMARK_SOURCE_ACQUISITION_CLEAN_ROOM_CURATOR_(V[1-9][0-9]*)_STANDARD_CURL_V[1-9][0-9]*\z/.match(proposed_tokens.first)
        assert!(token_match && token_match[1] == acquisition_version,
                "standard-curl acquisition version does not match the proposed authorization token")
      else
        assert!(grant["operations"] == profile["operations"],
                "read-only HTTPS operation enum contradicts its exact grant scope")
      end
      assert!(grant["targets"] == profile["targets"] &&
              grant["budget_or_external_effects"] == profile["budget_or_external_effects"],
              "read-only HTTPS operation enum contradicts its exact grant scope")
    else
      assert!(authorization["reserved_trigger"].nil? && authorization["proposal_mode"] == "NOT_APPLICABLE",
              "App approval cannot claim a Founder trigger")
      assert!(package["project_authorized"] == "YES" && package["app_filesystem_approval_required"] == "YES",
              "App approval must remain inside an existing project authorization")
      assert!(evidence["prospective_preflight"].nil?, "App approval cannot claim a prospective Founder preflight")
      assert!(!package["copy_ready_text_or_exact_steps"].match?(/authorize_[a-z0-9_]+/i),
              "App approval steps cannot contain a Founder authorization token")
      assert!(APP_OPERATION_TYPES.include?(authorization["operation_type"]), "App operation type invalid")
    end

    copy = package["copy_ready_text_or_exact_steps"]
    identity = package["canonical_identity"]
    artifact = package["governing_artifact"]
    required_copy_fragments = [identity["commit"], identity["tree"], artifact["path"],
                               artifact["byte_length"].to_s, artifact["sha256"],
                               authorization["reserved_trigger"].to_s, authorization["operation_type"]] +
                              grant.values_at("operations", "targets").flatten +
                              grant.values_at("duration", "budget_or_external_effects") +
                              authorization.values_at("risk_and_reversibility", "deny_or_defer_effect",
                                                      "authorization_expiry_or_consumption_rule",
                                                      "pass_lifecycle", "non_pass_lifecycle")
    required_copy_fragments.reject(&:empty?).each do |fragment|
      assert!(copy.include?(fragment), "copy-ready authorization omitted a declared identity, scope, or lifecycle boundary")
    end
  end

  def validate_material!(package)
    material = exact_object!(package["material"], %w[
      required_items why_agent_cannot_obtain_it submission_channel redaction_allowed
      validation_rule acceptable_alternative
    ], "material handoff")
    assert!(material["required_items"].is_a?(Array) && material["required_items"].length == 1,
            "material handoff must request exactly one current item")
    exact_object!(material["required_items"].first, %w[name source_or_version format minimum_completeness], "required material item")
    material["required_items"].first.each { |key, value| nonempty_string!(value, "required material #{key}") }
    %w[why_agent_cannot_obtain_it submission_channel redaction_allowed validation_rule acceptable_alternative].each do |key|
      nonempty_string!(material[key], "material #{key}")
    end
    copy = package["copy_ready_text_or_exact_steps"]
    required_copy_fragments = material["required_items"].first.values +
                              material.values_at("submission_channel", "validation_rule", "acceptable_alternative")
    required_copy_fragments.each do |fragment|
      assert!(copy.include?(fragment), "copy-ready material step omitted a declared requirement")
    end
  end

  def validate_class!(package, truth, run_validator:, current_user_request_token:)
    evidence = package["validator_evidence"]
    control = validate_control!(truth, evidence, run_validator: run_validator)
    case package["action_class"]
    when "NONE_CONTINUE"
      assert!(control["disposition"] == "NO_RESERVED_TRIGGER_CONTINUE_PHASE" &&
              control["founder_decision_required"] == false &&
              control.dig("reserved_trigger", "category") == "NONE" &&
              control["next_action_owner"] == "MASTER_CEO_AGENT" &&
              evidence["prospective_preflight"].nil?,
              "no-action handoff cannot silence a Founder action or prospective reserved effect")
      assert!(%w[COMPLETE CONTINUING].include?(package["current_state"]), "no-action handoff cannot wait for user")
      assert!(package["project_authorized"] == "YES" && package["app_filesystem_approval_required"] == "NO",
              "no-action handoff authority projection invalid")
      assert!(package["recommended_single_action"] == "NONE", "no-action handoff action must be NONE")
      assert!(package["copy_ready_text_or_exact_steps"] == NO_ACTION_SENTENCE, "no-action sentence drift")
      assert!(package["authorization"].nil? && package["material"].nil?, "no-action handoff cannot contain a request")
      assert!(package["user_request_evidence"].nil?, "no-action handoff cannot retain a user request")
    when "AUTHORIZATION_REQUIRED"
      assert!(package["current_state"] == "WAITING_USER", "authorization handoff must wait for user")
      assert!(package["write_not_executed"] == "YES", "authorization handoff must preserve restricted write/effect")
      nonempty_string!(package["recommended_single_action"], "recommended authorization action")
      nonempty_string!(package["copy_ready_text_or_exact_steps"], "copy-ready authorization text")
      assert!(package["copy_ready_text_or_exact_steps"].bytesize >= 80, "copy-ready authorization text is incomplete")
      assert!(package["material"].nil?, "authorization handoff cannot bundle a material request")
      validate_authorization!(package, truth, control, current_user_request_token)
    when "MATERIAL_REQUIRED"
      assert!(package["current_state"] == "WAITING_USER", "material handoff must wait for user")
      assert!(package["project_authorized"] == "YES" && package["app_filesystem_approval_required"] == "NO",
              "material handoff authority projection invalid")
      assert!(package["write_not_executed"] == "YES", "material handoff must preserve restricted work")
      nonempty_string!(package["recommended_single_action"], "recommended material action")
      nonempty_string!(package["copy_ready_text_or_exact_steps"], "copy-ready material step")
      assert!(package["authorization"].nil?, "material handoff cannot bundle an authorization request")
      assert!(package["user_request_evidence"].nil?, "material handoff cannot claim a Founder request")
      validate_material!(package)
    end
  end

  def marker_count(text, marker)
    text.scan(/^\s*#{Regexp.escape(marker)}:/).length
  end

  def validate_draft!(package, draft)
    text = draft.dup.force_encoding("UTF-8")
    assert!(text.valid_encoding?, "handoff draft encoding invalid")
    assert!(!text.match?(PLACEHOLDER), "handoff draft contains a placeholder")
    assert!(!text.match?(/<!--|-->/), "handoff draft cannot hide action markers in comments")
    assert!(!text.match?(/^\s*(?:另外|另一个|第二个|备选|或者|或请|同时|also|alternatively).*(?:动作|授权|上传|批准|发布|action|authorize|upload|release)/i),
            "handoff draft contains an unstructured second user action")
    MARKERS.each { |marker| assert!(marker_count(text, marker) == 1, "handoff draft must contain exactly one #{marker}") }
    if package["action_class"] == "NONE_CONTINUE"
      assert!(text.include?(NO_ACTION_SENTENCE), "handoff draft omitted the no-action sentence")
      assert!(text.include?("USER_ACTION_REQUIRED: false"), "handoff draft omitted the no-action flag")
      assert!(text.include?("RECOMMENDED_SINGLE_ACTION: NONE"), "handoff draft omitted the no-action decision")
      assert!(text.include?("COPY_READY_TEXT_OR_EXACT_STEPS: #{NO_ACTION_SENTENCE}"), "handoff draft omitted the no-action copy text")
      assert!(text.include?("AGENT_CONTINUATION_AFTER_ACTION: #{package['agent_continuation_after_action']}"),
              "handoff draft omitted the continuing agent action")
      assert!(!text.include?("USER_ACTION_REQUIRED: true"), "no-action draft contains a contradictory user request")
    else
      required_literals = {
        "USER_ACTION_REQUIRED: true" => "user-action flag",
        "RECOMMENDED_SINGLE_ACTION: #{package['recommended_single_action']}" => "recommended action",
        "COPY_READY_TEXT_OR_EXACT_STEPS: #{package['copy_ready_text_or_exact_steps']}" => "copy-ready text or steps",
        "AGENT_CONTINUATION_AFTER_ACTION: #{package['agent_continuation_after_action']}" => "agent continuation"
      }
      required_literals.each { |literal, label| assert!(text.include?(literal), "handoff draft omitted #{label}") }
      assert!(!text.include?("USER_ACTION_REQUIRED: false"), "user-action draft contains a contradictory no-action flag")
      assert!(text.scan(/^\s*RECOMMENDED_SINGLE_ACTION:/).length == 1, "handoff draft contains multiple recommended actions")
      assert!(text.scan(Regexp.new(Regexp.escape(package["copy_ready_text_or_exact_steps"]))).length == 1,
              "handoff draft must contain exactly one copy-ready action block")
      if package.dig("authorization", "authority_layer") == "FOUNDER_RESERVED"
        assert!(text.scan(FOUNDER_AUTHORIZATION_TOKEN).length == 1,
                "Founder handoff draft must contain exactly one authorization token")
      end
    end
  end

  def validate!(truth_path:, package_path:, draft_path:, test_fixture: false, current_user_request_token: nil)
    validate_truth_path!(truth_path) unless test_fixture
    truth_bytes = read_regular!(truth_path, "canonical Truth")
    truth = YAML.safe_load(truth_bytes, permitted_classes: [], permitted_symbols: [], aliases: false)
    assert!(truth.is_a?(Hash), "canonical Truth must be a mapping")
    package = parse_json!(read_regular!(package_path, "handoff package"), "handoff package")
    draft = read_regular!(draft_path, "handoff draft")
    validate_common!(package, truth_bytes)
    validate_class!(package, truth, run_validator: !test_fixture,
                    current_user_request_token: current_user_request_token)
    validate_draft!(package, draft)
    true
  end
end

if $PROGRAM_NAME == __FILE__
  options = { truth_path: FounderActionHandoff::DEFAULT_TRUTH }
  OptionParser.new do |parser|
    parser.on("--truth PATH") { |path| options[:truth_path] = File.expand_path(path) }
    parser.on("--package PATH") { |path| options[:package_path] = File.expand_path(path) }
    parser.on("--draft PATH") { |path| options[:draft_path] = File.expand_path(path) }
    parser.on("--current-user-request-token TOKEN") { |token| options[:current_user_request_token] = token }
  end.parse!

  begin
    FounderActionHandoff.assert!(options[:package_path], "--package is required")
    FounderActionHandoff.assert!(options[:draft_path], "--draft is required")
    FounderActionHandoff.validate!(**options)
    puts "FOUNDER_ACTION_HANDOFF_CHECK: PASS"
  rescue FounderActionHandoff::ValidationError, KeyError, TypeError => error
    warn "FOUNDER_ACTION_HANDOFF_CHECK: NON_PASS #{error.message}"
    exit 1
  end
end

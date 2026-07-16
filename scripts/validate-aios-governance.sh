#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT_DIR"

fail() {
  echo "AIOS GOVERNANCE FAIL: $*" >&2
  exit 1
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required"
command -v git >/dev/null 2>&1 || fail "git is required"

required_files=(
  AGENTS.md
  README.md
  ROADMAP.md
  docs/README.md
  docs/aios/README.md
  docs/aios/STRATEGIC_CONSTITUTION.md
  docs/aios/MASTER_EXECUTION_PROTOCOL.md
  docs/aios/EVALUATION_PROTOCOL.md
  docs/aios/MIGRATION_LEDGER.yaml
  docs/aios/BASELINE_ADAPTER_CONTRACT.md
  docs/aios/truth/project_state.yaml
  docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml
  docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml
  docs/aios/tasks/P1-003_PILOT_TASK_DATASET_AND_HIDDEN_SET_CURATION.yaml
  docs/aios/tasks/P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION.yaml
  docs/aios/tasks/P1-005_EVALUATION_MATRIX_AND_VTSR_COUNTING_VALIDATOR.yaml
  docs/aios/schemas/task-spec.schema.json
  docs/aios/schemas/environment-snapshot.schema.json
  docs/aios/schemas/system-configuration.schema.json
  docs/aios/schemas/run-record.schema.json
)

for file in "${required_files[@]}"; do
  [[ -s "$file" ]] || fail "required file missing or empty: $file"
done

ruby -ryaml -rjson -rdigest -rtime -e '
  truth = YAML.safe_load(File.read("docs/aios/truth/project_state.yaml"), aliases: false)
  task = YAML.safe_load(File.read("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml"), aliases: false)
  terminal_task = YAML.safe_load(File.read("docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml"), aliases: false)
  pilot_task_path = "docs/aios/tasks/P1-003_PILOT_TASK_DATASET_AND_HIDDEN_SET_CURATION.yaml"
  pilot_task_sha = "8dec9d7b12df2e31c62e9ce146938c8a192b4751ce3a9aced3ccd38414fd0aa6"
  pilot_task = YAML.safe_load(File.read(pilot_task_path), aliases: false)
  p1_004_task_path = "docs/aios/tasks/P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION.yaml"
  p1_004_task_sha = "0551602b5a330fc6d7920d048bba33caae9c5a0358c0bf57ef40cf7a63eaec6f"
  p1_004_task = YAML.safe_load(File.read(p1_004_task_path), aliases: false)
  p1_004_authorization_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-task-contract-20260716T002125Z/revision-2/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  p1_004_authorization_sha = "3979871bfa949c2f613f30c5169880e6bb02131f690298b446b0c831e147517e"
  p1_004_execution_root = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-parameterized-harness-admission-execution-20260716T002125Z"
  p1_004_terminal_paths = {
    "activation" => ["#{p1_004_execution_root}/activation/ACTIVATION_RECEIPT.json", "1fbbe9ae9a73581d739efdb392fca46c9e34ce66ef07161a74ee8f8545029ccb"],
    "activation_index" => ["#{p1_004_execution_root}/activation/PRE_EXECUTION_EVIDENCE_INDEX.json", "24929cd7fe456ec9e5ae6bd42f8768ab64cf20a7401e8dfd337b9a18741548de"],
    "stop" => ["#{p1_004_execution_root}/terminal/TERMINAL_STOP_RECORD.json", "ba3a50a97fe3bfd79c2568c13108828326dbba820cd2eef53e38fc54cd0bced3"],
    "manifest" => ["#{p1_004_execution_root}/terminal/TERMINAL_EVIDENCE_MANIFEST.json", "201bcf229c3179f882a066173401c3b335c7dc36fea1828fc43d7cda6b7a9320"],
    "seal" => ["#{p1_004_execution_root}/terminal/TERMINAL_SEAL.json", "2bb0a14c832567feb89f6fb71e6ab88c338a4308669928399e8c2364f6553875"],
    "cto" => ["#{p1_004_execution_root}/reviews/CTO_TERMINAL_REVIEW.json", "aa0c9a359e8ea19f93ff855691f031dd4a3c044aa3257af8470691181c9a9513"],
    "security" => ["#{p1_004_execution_root}/reviews/SECURITY_TERMINAL_REVIEW.json", "48bc8aa79a7f3eb2ad28077294339d8b5f3d90de4124354badbe528d54eff5b7"],
    "quality" => ["#{p1_004_execution_root}/reviews/QUALITY_TERMINAL_REVIEW.json", "06d512c7011422c7325d09ba9372aba55d74b6706a94232571ba29b9ecf5f0b9"]
  }
  p1_004_restore_receipt_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-004-terminal-closure-verification-20260716T041834Z/OFFSITE_RESTORE_VERIFICATION_RECEIPT.json"
  p1_004_restore_receipt_sha = "15e92ebef2a234652e1d42a2aaa7e42fdffc9466e5f4fd94447f136a0ab56368"
  active_task_path = "docs/aios/tasks/P1-005_EVALUATION_MATRIX_AND_VTSR_COUNTING_VALIDATOR.yaml"
  active_task_sha = "e17340610bc8a53b887c4699ba13ab6b4e89e9caedb0f56c5375bf8eac122a2c"
  active_task = YAML.safe_load(File.read(active_task_path), aliases: false)
  active_authorization_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-005-evaluation-matrix-vtsr-execution-20260716T051135Z/activation/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  active_authorization_sha = "e4af3f5b7696232a37b818ae12bf0c6f04872f07978ca5c21cfee3c147068559"
  p1_005_terminal_stop_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-005-evaluation-matrix-vtsr-execution-20260716T051135Z/terminal/TERMINAL_STOP_RECORD.json"
  p1_005_terminal_stop_sha = "7ba972bc2514e158ea491d703fc0979b0da34c7e840c4e90e18874da62b65ba0"
  p1_005_terminal_manifest_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-005-evaluation-matrix-vtsr-execution-20260716T051135Z/terminal/TERMINAL_EVIDENCE_MANIFEST.json"
  p1_005_terminal_manifest_sha = "4be9f4ad4b25cbd2e4b6e3411e30cfc51ca1330c13a36bbca7f2c2450ec5be09"
  p1_005_offsite_receipt_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-005-evaluation-matrix-vtsr-execution-20260716T051135Z/terminal/OFFSITE_TERMINAL_VERIFICATION_RECEIPT.json"
  p1_005_offsite_receipt_sha = "534c0b2dfd830fa465723700e88a70264cb156d281e2ebb0b4ed560867bf0b9d"
  abort "P1-005 Founder authorization missing" unless File.file?(active_authorization_path)
  active_authorization = JSON.parse(File.read(active_authorization_path))
  p1_005_terminal_stop = JSON.parse(File.read(p1_005_terminal_stop_path))
  p1_005_terminal_manifest = JSON.parse(File.read(p1_005_terminal_manifest_path))
  p1_005_offsite_receipt = JSON.parse(File.read(p1_005_offsite_receipt_path))
  authorization_capture_path = "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  authorization_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/FOUNDER_EXECUTION_AUTHORIZATION_RECORD.json"
  authorization_sha = "1082f0a81eb41a1fae9a1767d421bb0fe8f11810bccba197ad18e3e430762a1b"
  abort "P1-003 Founder authorization missing" unless File.file?(authorization_path)
  pilot_authorization = JSON.parse(File.read(authorization_path))
  parent_binding_capture_path = "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/IMPLEMENTATION_PARENT_BINDING_RECORD.json"
  parent_binding_path = "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-execution-authorization-20260715T125627Z/IMPLEMENTATION_PARENT_BINDING_RECORD.json"
  parent_binding_sha = "ead76e3b06eb2c509ec0ee66df72af4756be946f5f75f2801d4b75a92a1b6774"
  abort "P1-003 implementation parent binding missing" unless File.file?(parent_binding_path)
  parent_binding = JSON.parse(File.read(parent_binding_path))
  hidden_public_receipt_path = "/Volumes/lijp/SourceLens-AIOS-P1-003-terminal-relocation-20260715T145418Z/visible/evidence/HIDDEN_OFFSITE_PUBLIC_RECEIPT.json"
  hidden_public_receipt_sha = "f249c9703de977e513890b0cf592ce52ce050996482e615270d22add4067b8a7"
  terminal_evidence_paths = {
    "classification_correction" => [
      "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-pilot-dataset-v0.1/integration/P1_003_TERMINAL_CLASSIFICATION_CORRECTION_RECORD.json",
      "4ec9307bb7b4ea2fc807d8e34769592e8a1bf661c77e4962699f39328cc9ed8c"
    ],
    "evidence_manifest_v2" => [
      "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-pilot-dataset-v0.1/integration/TERMINAL_EVIDENCE_MANIFEST_V2.json",
      "76083450ff7da28eef4f264b3cb15c684207af69997b89d3515ae695d6c9ddf1"
    ],
    "cto_review" => [
      "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-pilot-dataset-v0.1/reviews/cto/TERMINAL_CLASSIFICATION_REVIEW.json",
      "215788a95673940f221b37242d54eb59177c4c7f9c5595b0affa1368065533c5"
    ],
    "quality_review" => [
      "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-pilot-dataset-v0.1/reviews/quality/TERMINAL_CLASSIFICATION_REVIEW.json",
      "f37e71d03c13a9e5ab56f46537a40c3eee58831692dcc28e57c388e6a259da0b"
    ],
    "prior_relocation_stop" => [
      "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-terminal-relocation-20260715T145418Z/P1_003_TERMINAL_RELOCATION_STOP_RECORD.json",
      "f125fb6cee24388f0ec4113df2792b5c89ed3f706bd9d3fd9dd0d08e94710908"
    ],
    "overall_recovery_stop" => [
      "/Users/lijunpeng/Developer/.sourcelens-audit/p1-003-terminal-relocation-20260715T145418Z/P1_003_STOPPED_STATE_RECOVERY_AND_CANONICAL_CUTOVER_TERMINAL_STOP_RECORD.json",
      "fd2b0b1947a9fbbf8f10294106a7abeadd3f42658b6f629fab2dfdd2567d89fa"
    ]
  }
  goal_path = "/Users/lijunpeng/.codex/attachments/37671a04-0182-4aff-9f0a-c044c5b3cfa3/goal-objective.md"
  abort "active Goal body missing" unless File.file?(goal_path)
  ledger = YAML.safe_load(File.read("docs/aios/MIGRATION_LEDGER.yaml"), aliases: false)

  expected_hashes = {
    "docs/aios/STRATEGIC_CONSTITUTION.md" => "040196be12532b8c3661665995d3e79a28d268a1ecc991623380f0939f468485",
    "docs/aios/MASTER_EXECUTION_PROTOCOL.md" => "47c444c50c7521a7515dfb2fbee0c8c81cc72b32c42eba549d080eeb0c1bcedf",
    "docs/aios/EVALUATION_PROTOCOL.md" => "da029143561fbb3c213d4a358b25e085542c6cd26ae8150a53cbb5998177eed8",
    "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml" => "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f",
    "docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml" => "c303f045e67dc1f76d51a5789eeb0573021bdcd9d17cd169d7448f64f91a87d8",
    pilot_task_path => pilot_task_sha,
    p1_004_task_path => p1_004_task_sha,
    p1_004_authorization_path => p1_004_authorization_sha,
    p1_004_restore_receipt_path => p1_004_restore_receipt_sha,
    active_task_path => active_task_sha,
    active_authorization_path => active_authorization_sha,
    p1_005_terminal_stop_path => p1_005_terminal_stop_sha,
    p1_005_terminal_manifest_path => p1_005_terminal_manifest_sha,
    p1_005_offsite_receipt_path => p1_005_offsite_receipt_sha,
    authorization_path => authorization_sha,
    parent_binding_path => parent_binding_sha,
    "evaluation-harness/fixtures/oracle/FREEZE_RECEIPT.json" => "ef7f9807795a685d0aa92fc19248ed0101362861ad7d71e4fdcdbb9df0b840c6",
    "evaluation-harness/recording/aios-p1-001-evidence/evidence-manifest.json" => "e1f735816c18ab7631fa1d0b771deccc25564074350d1d74e67975d187ef3952"
  }
  terminal_evidence_paths.each_value { |path, expected| expected_hashes[path] = expected }
  p1_004_terminal_paths.each_value { |path, expected| expected_hashes[path] = expected }
  expected_hashes.each do |path, expected|
    actual = Digest::SHA256.file(path).hexdigest
    abort "authority hash drift: #{path}" unless actual == expected
  end

  abort "truth schema drift" unless truth["schema_version"] == 3
  abort "phase must be P1" unless truth.dig("project", "current_phase") == "P1"
  abort "P0 must be complete" unless truth.dig("project", "p0_status") == "COMPLETE"
  abort "P1 entry must be authorized" unless truth.dig("project", "p1_entry_status") == "AUTHORIZED"
  abort "P1 execution state drift" unless truth.dig("project", "p1_execution_status") == "NO_CURRENT_TASK"
  abort "canonical repository drift" unless truth.dig("project", "canonical_repository") == "/Users/lijunpeng/Developer/SourceLens-AIOS"
  abort "old Desktop repository remains canonical" if truth.dig("project", "canonical_repository") == "/Users/lijunpeng/Desktop/cc/project/SourceLens-AIOS"
  abort "canonical cutover parent commit drift" unless truth.dig("project", "canonical_cutover_parent_commit") == "65157b6f771c3a95486144ab712c3a99f9d06845"
  abort "canonical cutover parent tree drift" unless truth.dig("project", "canonical_cutover_parent_tree") == "2409b9abacb276a0e977b65f6dcb0d1bdb6f1d30"
  abort "accepted candidate commit drift" unless truth.dig("project", "accepted_harness_candidate_commit") == "02342da942e291eaa65230f824fcf47eae8f8a30"
  abort "accepted candidate tree drift" unless truth.dig("project", "accepted_harness_candidate_tree") == "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc"
  abort "Goal control-plane observation drift" unless truth.dig("goal", "control_plane_status_observed") == "ACTIVE"
  abort "Goal canonical hash drift" unless truth.dig("goal", "observed_body_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "Goal raw hash drift" unless truth.dig("goal", "observed_raw_body_sha256") == "9b59ffc6919473b596f09a96afc1e8684f076f5ac32c6014ac96344a496cd0d8"
  abort "Goal canonicalization drift" unless truth.dig("goal", "body_canonicalization") == "UTF8_LF_WITH_EXACTLY_ONE_TRAILING_LF"
  abort "Goal identity state drift" unless truth.dig("goal", "identity_status") == "FOUNDER_MANUALLY_INSTALLED_LONG_TERM_GOAL_IDENTITY_PRESERVED"
  active_task_id = "AIOS-P1-005_EVALUATION_MATRIX_AND_VTSR_COUNTING_VALIDATOR"
  abort "Goal current Task authority drift" unless truth.dig("goal", "current_task_authority") == "NONE"
  goal_bytes = File.binread(goal_path)
  abort "Goal raw bytes drift" unless Digest::SHA256.hexdigest(goal_bytes) == "9b59ffc6919473b596f09a96afc1e8684f076f5ac32c6014ac96344a496cd0d8"
  canonical_goal = goal_bytes.force_encoding("UTF-8").gsub("\r\n", "\n").gsub("\r", "\n").sub(/\n*\z/, "\n")
  abort "Goal canonical bytes drift" unless canonical_goal.valid_encoding? && Digest::SHA256.hexdigest(canonical_goal) == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  terminal_task_id = "AIOS-P1-002_B0_ADAPTER_CONFORMANCE"
  terminal_task_path = "docs/aios/tasks/P1-002_B0_ADAPTER_CONFORMANCE.yaml"
  terminal_task_sha = "c303f045e67dc1f76d51a5789eeb0573021bdcd9d17cd169d7448f64f91a87d8"
  pilot_task_id = "AIOS-P1-003_PILOT_TASK_DATASET_AND_HIDDEN_SET_CURATION"
  abort "current Task must be NONE" unless truth.dig("active_work", "current_task") == "NONE" && truth.dig("active_work", "current_task_status") == "NONE"
  abort "current Task Contract must be null" unless truth.dig("active_work", "current_task_contract").nil? && truth.dig("active_work", "current_task_contract_sha256").nil?
  abort "current execution authorization must be null" unless truth.dig("active_work", "current_execution_authorization").nil? && truth.dig("active_work", "current_execution_authorization_sha256").nil?
  abort "current execution nonce must be empty" unless truth.dig("active_work", "execution_nonce").nil? && truth.dig("active_work", "execution_nonce_status") == "NONE"
  abort "current Task resources must be empty" unless truth.dig("active_work", "task_branch").nil? && truth.dig("active_work", "task_worktree").nil? && truth.dig("active_work", "execution_evidence_root").nil? && truth.dig("active_work", "offsite_target").nil?
  abort "next action drift" unless truth.dig("active_work", "next_eligible_action") == "FOUNDER_AUTHORIZE_NEXT_P1_REAL_ENGINEERING_TASK"
  abort "P1 implementation boundary drift" unless truth.dig("p1_boundary", "allowed_now") == [
    "No current Task is authorized; active_work.current_task is NONE.",
    "P1-005 is terminal non-PASS, cannot resume, retry or continue through a successor/replacement/correction chain, and no partial implementation is accepted.",
    "P1-003 is terminal, its hidden custody is quarantined historical risk, and it cannot be resumed, retried, backfilled, replaced or represented as PASS.",
    "P1-004 is terminal, not accepted, cannot be resumed, retried or continued through a successor/correction chain, and its Worker candidate remains off main.",
    "B0/B1/B2/A0 execution, P2/P3 entry, automatic canonical main advance and all unapproved external effects remain unauthorized."
  ]
  abort "P1-003 dataset claim boundary drift" unless truth.dig("claim_boundary", "p1_pilot_task_dataset") == "TERMINAL_STOPPED_NOT_ACCEPTED" && truth.dig("claim_boundary", "p1_pilot_task_dataset_claims") == 0
  abort "P1-003 eligible task claim drift" unless truth.dig("claim_boundary", "p1_pilot_task_dataset_eligible_tasks") == "0_OF_8"
  abort "P1-003 Evidence integrity drift" unless truth.dig("claim_boundary", "p1_pilot_task_acquisition_evidence_integrity") == "FAIL"
  abort "P1-003 exact closure falsely claimed" unless truth.dig("claim_boundary", "p1_pilot_task_exact_request_and_byte_closure") == "UNKNOWN_NOT_PASS"
  abort "P1-003 hidden custody quarantine drift" unless truth.dig("claim_boundary", "p1_pilot_task_hidden_custody") == "QUARANTINED_HISTORICAL_RISK"
  abort "P1-004 acceptance falsely claimed" unless truth.dig("claim_boundary", "p1_004_parameterized_harness_admission") == "TERMINAL_STOPPED_NOT_ACCEPTED"
  abort "P1-004 Worker candidate falsely accepted" unless truth.dig("claim_boundary", "p1_004_worker_candidate_accepted") == false
  abort "P1-004 capability claim widened" unless truth.dig("claim_boundary", "p1_004_capability_claims") == 0
  abort "P1-005 falsely accepted" unless truth.dig("claim_boundary", "p1_005_evaluation_matrix_vtsr_validator") == "TERMINAL_STOPPED_NOT_ACCEPTED"
  abort "P1-005 candidate falsely created" unless truth.dig("claim_boundary", "p1_005_candidate_created") == false
  abort "P1-005 capability claim widened" unless truth.dig("claim_boundary", "p1_005_capability_claims") == 0

  abort "P1-005 Task id or phase drift" unless active_task["task_id"] == active_task_id && active_task["phase"] == "P1"
  abort "P1-005 frozen Contract bytes changed authorization semantics" unless active_task["status"] == "FINAL_CONTRACT_CANDIDATE_AWAITING_FOUNDER_EXECUTION_AUTHORIZATION" && active_task["execution_authorized"] == false
  abort "P1-005 Goal binding drift" unless active_task.dig("authority_binding", "long_term_goal_canonical_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "P1-005 source parent drift" unless active_task.dig("source", "authorization_parent_commit") == "c1dc6fdc7c8eaa7728c27caad8013631babecc74" && active_task.dig("source", "authorization_parent_tree") == "0aaa9a7156250d02d3e0fd9a92f7f999237176c0"
  abort "P1-005 runtime boundary drift" unless active_task.dig("runtime_boundary", "executable") == "/usr/local/bin/node" && active_task.dig("runtime_boundary", "executable_sha256") == "c5548e7a991a5c90170a29843ffc46df4643e29141f3cbb035f60295cf2bc882"
  %w[network provider secrets remote production public_release].each { |field| abort "P1-005 external boundary widened: #{field}" unless active_task.dig("runtime_boundary", field) == "forbidden" }
  abort "P1-005 baseline execution widened" unless active_task.dig("budget", "live_baseline_runs") == 0 && active_task.dig("budget", "measurement_retries") == 0
  abort "P1-005 external budget widened" unless active_task.dig("budget", "network_requests") == 0 && active_task.dig("budget", "provider_calls") == 0 && active_task.dig("budget", "secrets_accessed") == 0 && active_task.dig("budget", "remote_writes") == 0 && active_task.dig("budget", "production_effects") == 0
  abort "P1-005 authorization state drift" unless active_authorization["status"] == "AUTHORIZED_ACTIVE" && active_authorization["task_id"] == active_task_id
  abort "P1-005 authorization Contract drift" unless active_authorization.dig("task_contract", "sha256") == active_task_sha && active_authorization.dig("task_contract", "byte_length") == 31_858
  abort "P1-005 authorization Goal drift" unless active_authorization.dig("authority", "goal_canonical_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "P1-005 authorization nonce drift" unless active_authorization["consumed_single_use_nonce"] == "3642ac4b49ff5d7d6c97068d0094dc54b36aa2f5d3ab67485b77afed7efe5117"
  abort "P1-005 automatic continuation enabled" unless active_authorization["automatic_main_advance"] == false && active_authorization["automatic_next_task"] == false
  abort "P1-005 later scope enabled" unless active_authorization["b0_b1_b2_a0_authorized"] == false && active_authorization["p2_p3_authorized"] == false
  p1_005_terminal_state = "TERMINAL_STOPPED_DURING_QUALITY_FREEZE_OUT_OF_SCOPE_WRITE"
  abort "P1-005 stop state drift" unless p1_005_terminal_stop["terminal_state"] == p1_005_terminal_state
  abort "P1-005 stop reason drift" unless p1_005_terminal_stop.dig("stop_condition", "triggered") == true && p1_005_terminal_stop.dig("stop_condition", "failure_classification") == "EXECUTION_SCOPE_COMPLIANCE_FAILURE"
  abort "P1-005 nonce not retired" unless p1_005_terminal_stop.dig("authority_bindings", "nonce_terminal_status") == "RETIRED_AFTER_TASK_STOP"
  abort "P1-005 terminal manifest drift" unless p1_005_terminal_manifest["terminal_state"] == p1_005_terminal_state && p1_005_terminal_manifest["artifact_count"] == 15
  abort "P1-005 offsite verification not PASS" unless p1_005_offsite_receipt["result"] == "PASS" && p1_005_offsite_receipt["package_classification"] == "TERMINAL_NON_PASS_NOT_CANDIDATE"
  p1_005_history = truth.dig("task_history", "aios_p1_005")
  abort "P1-005 terminal history missing" unless p1_005_history.is_a?(Hash)
  abort "P1-005 terminal history drift" unless p1_005_history["status"] == p1_005_terminal_state && p1_005_history["execution_authorized"] == false && p1_005_history["execution_nonce_status"] == "RETIRED_AFTER_TASK_STOP" && p1_005_history["resume_retry_successor_allowed"] == false
  abort "P1-005 candidate or capability falsely claimed" unless p1_005_history.dig("implementation_state", "candidate_created") == false && p1_005_history["capability_claims"] == 0 && p1_005_history["founder_gate_status"] == "NOT_REACHED"
  abort "P1-005 terminal Evidence binding drift" unless p1_005_history.dig("terminal_evidence", "stop_record_sha256") == p1_005_terminal_stop_sha && p1_005_history.dig("terminal_evidence", "evidence_manifest_sha256") == p1_005_terminal_manifest_sha
  abort "P1-005 offsite custody drift" unless p1_005_history.dig("terminal_cleanup", "restore_verification_receipt_sha256") == p1_005_offsite_receipt_sha && p1_005_history.dig("terminal_cleanup", "restore_status") == "PASS"

  abort "P1-003 Task id drift" unless pilot_task["task_id"] == pilot_task_id
  abort "P1-003 phase drift" unless pilot_task["phase"] == "P1"
  abort "P1-003 contract bytes self-authorized" unless pilot_task["status"] == "DRAFT_NOT_AUTHORIZED" && pilot_task["execution_authorized"] == false
  abort "P1-003 contract draft boundary drift" unless pilot_task.dig("founder_selection", "authorization_effect") == "DRAFT_ONLY" && pilot_task.dig("founder_selection", "network_authorized") == false && pilot_task.dig("founder_selection", "data_acquisition_authorized") == false && pilot_task.dig("founder_selection", "experiment_authorized") == false
  abort "P1-003 selected parent drift" unless pilot_task.dig("source", "selected_parent_commit") == "4fc43418755c6d63b8d6cecd04a23e0101259d65" && pilot_task.dig("source", "selected_parent_tree") == "d9475b5d07fb80dd981bfb49e067edffba2d5b86"
  expected_sync_paths = [
    pilot_task_path,
    "docs/aios/truth/project_state.yaml",
    "scripts/validate-aios-governance.sh",
    "scripts/check-p1-safety-boundary.sh",
    "docs/PROJECT_CODE_MAP.md"
  ]
  abort "P1-003 governance sync paths drift" unless pilot_task.dig("implementation_scope", "pre_execution_governance_sync_paths") == expected_sync_paths
  abort "P1-003 task count drift" unless pilot_task.dig("dataset_identity", "exact_curation_eligible_task_count") == 8 && pilot_task.dig("dataset_identity", "split_counts") == {"development" => 4, "validation" => 2, "hidden" => 2}
  abort "P1-003 model budget widened" unless pilot_task.dig("budget", "model_calls") == 0 && pilot_task.dig("budget", "provider_calls") == 0 && pilot_task.dig("budget", "baseline_runs") == 0
  abort "P1-003 remote or production budget widened" unless pilot_task.dig("budget", "remote_writes") == 0 && pilot_task.dig("budget", "production_effects") == 0 && pilot_task.dig("budget", "public_releases") == 0
  abort "P1-003 new runtime boundary widened" unless pilot_task.dig("budget", "new_runtime_services") == 0 && pilot_task.dig("budget", "new_sandbox_or_execution_carrier") == 0
  abort "P1-003 network draft boundary drift" unless pilot_task.dig("proposed_network_boundary", "current_status") == "NOT_AUTHORIZED_BY_THIS_DRAFT"
  abort "P1-003 accepted harness became writable" unless (pilot_task.dig("implementation_scope", "immutable_inputs") || []).include?("evaluation-harness/recording/aios-p1-001-evidence/**")
  abort "P1-003 claim boundary widened" unless pilot_task.dig("claim_boundary", "does_not_prove").include?("P1 exit") && pilot_task.dig("claim_boundary", "does_not_prove").include?("B0, B1, B2 or A0 performance")

  abort "P1-003 authorization status drift" unless pilot_authorization["status"] == "ACTIVE" && pilot_authorization["authority"] == "Human Founder"
  abort "P1-003 authorization Task binding drift" unless pilot_authorization["task_id"] == pilot_task_id && pilot_authorization["task_contract_sha256"] == pilot_task_sha
  abort "P1-003 authorization Goal binding drift" unless pilot_authorization["goal_raw_body_sha256"] == "9b59ffc6919473b596f09a96afc1e8684f076f5ac32c6014ac96344a496cd0d8" && pilot_authorization["goal_canonical_body_sha256"] == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "P1-003 authorization authority binding drift" unless pilot_authorization["constitution_sha256"] == "040196be12532b8c3661665995d3e79a28d268a1ecc991623380f0939f468485" && pilot_authorization["master_execution_protocol_sha256"] == "47c444c50c7521a7515dfb2fbee0c8c81cc72b32c42eba549d080eeb0c1bcedf" && pilot_authorization["evaluation_protocol_sha256"] == "da029143561fbb3c213d4a358b25e085542c6cd26ae8150a53cbb5998177eed8"
  abort "P1-003 authorization parent drift" unless pilot_authorization["authorized_parent_commit"] == "4fc43418755c6d63b8d6cecd04a23e0101259d65" && pilot_authorization["authorized_parent_tree"] == "d9475b5d07fb80dd981bfb49e067edffba2d5b86"
  abort "P1-003 authorization nonce drift" unless pilot_authorization["execution_nonce"] == "b56ae67c0aa13fff47c396bc7c064d74a56bb93a6ab27ebeebfb69f9997894c9"
  abort "P1-003 capture-time authorization window drift" unless pilot_authorization["effective_from_utc"] == "2026-07-15T12:56:27Z" && pilot_authorization["expires_at_utc"] == "2026-07-22T12:56:27Z"
  expected_scope = {
    "governance_only_pre_execution_sync" => true,
    "one_task_branch" => "task/AIOS-P1-003-pilot-dataset-curation",
    "one_task_worktree" => "/Users/lijunpeng/Desktop/cc/project/.sourcelens-worktrees/AIOS-P1-003-pilot-dataset-curation",
    "dataset_curation" => true,
    "anonymous_read_only_network_acquisition" => true,
    "offline_fixed_digest_disposable_oci_verification" => true,
    "evidence_and_independent_review" => true,
    "offsite_package_and_restore_verification" => true,
    "main_advance" => false,
    "baseline_execution" => false
  }
  abort "P1-003 authorization scope drift" unless pilot_authorization["authorized_scope"] == expected_scope
  abort "P1-003 offsite binding drift" unless pilot_authorization.dig("offsite_binding", "path") == "/Volumes/lijp/SourceLens-AIOS-P1-003-offsite-20260715T125627Z" && pilot_authorization.dig("offsite_binding", "expected_volume_uuid") == "2D3D7BCD-5BC5-3D2A-B853-F1FA95D290F8"
  abort "P1-003 offsite precondition weakened" unless pilot_authorization.dig("offsite_binding", "write_precondition") == "VOLUME_MOUNTED_AND_UUID_EXACT_MATCH_AND_TARGET_PATH_ABSENT" && pilot_authorization.dig("offsite_binding", "non_match_effect") == "STOP_BEFORE_OFFSITE_WRITE"
  expected_budget = {
    "engineering_hours" => 32, "calendar_days" => 7, "maximum_candidates_screened" => 24,
    "maximum_external_repositories_acquired" => 4, "maximum_anonymous_network_requests" => 120,
    "maximum_total_inbound_bytes" => 1073741824, "maximum_external_staging_bytes" => 4294967296,
    "in_task_correction_passes" => 2, "model_calls" => 0, "provider_calls" => 0,
    "baseline_runs" => 0, "remote_writes" => 0, "production_effects" => 0,
    "public_releases" => 0
  }
  abort "P1-003 authorization budget drift" unless pilot_authorization["budgets"] == expected_budget
  %w[canonical\ main\ advance B0/B1/B2/A0\ execution P1\ exit P2\ or\ P3\ entry Provider\ or\ Secret\ use authenticated\ network remote\ write production\ effect public\ release Supervisor\ or\ Root\ Custody new\ execution\ carrier\ or\ sandbox\ design successor,\ replacement,\ normalization\ or\ correction\ chain].each do |boundary|
    abort "P1-003 non-authorization missing: #{boundary}" unless pilot_authorization.fetch("explicit_non_authorizations").include?(boundary.tr("\\", ""))
  end

  expected_parent_binding = {
    "schema_version" => "1.0",
    "record_type" => "sourcelens_aios_implementation_parent_binding",
    "status" => "ACTIVE_AFTER_CANONICAL_TRUTH_ACTIVATION",
    "authority" => "Human Founder",
    "authority_source" => "CODEX_THREAD_FOUNDER_MESSAGE",
    "authority_source_message" => "\u6388\u6743",
    "authority_source_message_sha256" => "fce3771b1b29f5b8c466a7b4e76e01f1ab8436b481c706af4563f5819cc1e017",
    "created_at_utc" => "2026-07-15T13:09:19Z",
    "parent_authorization_record" => authorization_capture_path,
    "parent_authorization_sha256" => authorization_sha,
    "task_id" => pilot_task_id,
    "task_contract_sha256" => pilot_task_sha,
    "execution_nonce" => "b56ae67c0aa13fff47c396bc7c064d74a56bb93a6ab27ebeebfb69f9997894c9",
    "effective_from_utc" => "2026-07-15T12:56:27Z",
    "expires_at_utc" => "2026-07-22T12:56:27Z",
    "governance_sync_commit" => "b9cbbf64b7fa98e7dfd30f752085f40104571957",
    "governance_sync_tree" => "0580f4de27e4c6b18dbb7f170ba659e2b38ffba2",
    "implementation_branch_initial_ref" => "b9cbbf64b7fa98e7dfd30f752085f40104571957",
    "implementation_branch" => "task/AIOS-P1-003-pilot-dataset-curation",
    "implementation_worktree" => "/Users/lijunpeng/Desktop/cc/project/.sourcelens-worktrees/AIOS-P1-003-pilot-dataset-curation",
    "binding_effect" => "BINDS_THE_ALREADY_AUTHORIZED_TASK_TO_THE_CAUSALLY_LATER_GOVERNANCE_SYNC_COMMIT_AND_TREE_WITHOUT_SCOPE_EXPANSION",
    "scope_expansion" => false,
    "main_advance" => false,
    "baseline_execution" => false,
    "activation_precondition" => "CANONICAL_TRUTH_AND_VALIDATORS_BIND_THIS_RECORD_SHA256_AND_REMAIN_PASS",
    "drift_effect" => "STOP_BEFORE_BRANCH_OR_WORKTREE_CREATION"
  }
  abort "P1-003 implementation parent record drift" unless parent_binding == expected_parent_binding

  pilot_history = truth.dig("task_history", "aios_p1_003")
  abort "P1-003 terminal history missing" unless pilot_history.is_a?(Hash)
  expected_pilot_history = {
    "task_id" => pilot_task_id,
    "contract" => pilot_task_path,
    "task_contract_sha256" => pilot_task_sha,
    "status" => "TERMINAL_STOPPED_BEFORE_INTEGRATION_ACQUISITION_EVIDENCE_INTEGRITY_FAILURE",
    "execution_authorized" => false,
    "original_execution_authorization_status" => "CONSUMED_AND_TERMINATED",
    "curation_eligible_tasks_completed" => 0,
    "curation_eligible_tasks_required" => 8,
    "retained_complete_request_records" => 37,
    "conservative_actual_request_minimum" => 39,
    "exact_actual_request_population" => "UNKNOWN",
    "exact_total_inbound_bytes" => "UNKNOWN",
    "evidence_integrity" => "FAIL",
    "candidate_status" => "NOT_CREATED",
    "final_candidate_review_status" => "NOT_PERFORMED",
    "founder_gate_status" => "NOT_REACHED",
    "main_advanced" => false,
    "resume_retry_successor_allowed" => false
  }
  expected_pilot_history.each do |field, expected|
    abort "P1-003 terminal history drift: #{field}" unless pilot_history[field] == expected
  end

  pilot_authorization_history = pilot_history.fetch("authorization_history")
  abort "P1-003 capture-time authorization locator rewritten" unless pilot_authorization_history["original_capture_time_authorization_path"] == authorization_capture_path
  abort "P1-003 current authorization custody locator drift" unless pilot_authorization_history["current_custody_authorization_path"] == authorization_path
  abort "P1-003 authorization history hash drift" unless pilot_authorization_history["authorization_sha256"] == authorization_sha
  abort "P1-003 capture-time parent binding locator rewritten" unless pilot_authorization_history["original_capture_time_parent_binding_path"] == parent_binding_capture_path
  abort "P1-003 current parent binding custody locator drift" unless pilot_authorization_history["current_custody_parent_binding_path"] == parent_binding_path
  abort "P1-003 parent binding history hash drift" unless pilot_authorization_history["parent_binding_sha256"] == parent_binding_sha
  abort "P1-003 execution nonce not retired" unless pilot_authorization_history["execution_nonce_status"] == "RETIRED"

  pilot_evidence = pilot_history.fetch("terminal_evidence")
  expected_pilot_evidence_fields = {
    "classification_correction_path" => terminal_evidence_paths.fetch("classification_correction")[0],
    "classification_correction_sha256" => terminal_evidence_paths.fetch("classification_correction")[1],
    "evidence_manifest_v2_path" => terminal_evidence_paths.fetch("evidence_manifest_v2")[0],
    "evidence_manifest_v2_sha256" => terminal_evidence_paths.fetch("evidence_manifest_v2")[1],
    "cto_terminal_classification_review_path" => terminal_evidence_paths.fetch("cto_review")[0],
    "cto_terminal_classification_review_sha256" => terminal_evidence_paths.fetch("cto_review")[1],
    "quality_terminal_classification_review_path" => terminal_evidence_paths.fetch("quality_review")[0],
    "quality_terminal_classification_review_sha256" => terminal_evidence_paths.fetch("quality_review")[1],
    "prior_relocation_stop_path" => terminal_evidence_paths.fetch("prior_relocation_stop")[0],
    "prior_relocation_stop_sha256" => terminal_evidence_paths.fetch("prior_relocation_stop")[1],
    "overall_recovery_stop_path" => terminal_evidence_paths.fetch("overall_recovery_stop")[0],
    "overall_recovery_stop_sha256" => terminal_evidence_paths.fetch("overall_recovery_stop")[1]
  }
  expected_pilot_evidence_fields.each do |field, expected|
    abort "P1-003 terminal Evidence binding drift: #{field}" unless pilot_evidence[field] == expected
  end

  correction = JSON.parse(File.read(terminal_evidence_paths.fetch("classification_correction")[0]))
  manifest_v2 = JSON.parse(File.read(terminal_evidence_paths.fetch("evidence_manifest_v2")[0]))
  cto_review = JSON.parse(File.read(terminal_evidence_paths.fetch("cto_review")[0]))
  quality_review = JSON.parse(File.read(terminal_evidence_paths.fetch("quality_review")[0]))
  prior_relocation_stop = JSON.parse(File.read(terminal_evidence_paths.fetch("prior_relocation_stop")[0]))
  overall_recovery_stop = JSON.parse(File.read(terminal_evidence_paths.fetch("overall_recovery_stop")[0]))
  exact_terminal_status = "TERMINAL_STOPPED_BEFORE_INTEGRATION_ACQUISITION_EVIDENCE_INTEGRITY_FAILURE"
  abort "P1-003 correction status drift" unless correction["corrected_status"] == exact_terminal_status && correction["task_remains_terminal"] == true
  population = correction.dig("correct_primary_reason", "population")
  abort "P1-003 retained request population drift" unless population["retained_complete_request_records"] == 37 && population["conservative_actual_request_minimum"] == 39
  abort "P1-003 unknown request/byte boundary lost" unless population["exact_actual_request_population"] == "UNKNOWN" && population["exact_total_inbound_bytes"] == "UNKNOWN"
  completion = correction.fetch("completion_projection")
  abort "P1-003 candidate or gate falsely claimed" unless completion["curation_eligible_tasks_completed"] == 0 && completion["curation_eligible_tasks_required"] == 8 && completion["candidate"] == "NOT_CREATED" && completion["founder_gate"] == "NOT_PERFORMED" && completion["main_advance"] == false
  abort "P1-003 terminal manifest status drift" unless manifest_v2["status"] == exact_terminal_status
  abort "P1-003 CTO terminal classification drift" unless cto_review.dig("aggregate_decision", "supported_terminal_classification") == "ACQUISITION_EVIDENCE_INTEGRITY_FAILURE" && cto_review.dig("aggregate_decision", "task_should_remain_terminal_stopped") == true && cto_review["status"] == "NOT_A_FINAL_CANDIDATE_REVIEW"
  abort "P1-003 Quality terminal classification drift" unless quality_review.dig("aggregate_verdict", "correct_terminal_classification") == "ACQUISITION_EVIDENCE_INTEGRITY_FAILURE" && quality_review.dig("aggregate_verdict", "task_terminal_state") == "TERMINAL_STOP_REQUIRED" && quality_review["status"] == "NOT_A_FINAL_CANDIDATE_REVIEW"
  abort "prior relocation Stop Record drift" unless prior_relocation_stop["status"] == "TERMINAL_STOPPED_AFTER_INTEGRATION_CONTEXT_HIDDEN_ROOT_DIRECTORY_ENUMERATION_BOUNDARY_BREACH"
  abort "overall recovery Stop Record task state drift" unless overall_recovery_stop["task_state"] == exact_terminal_status
  abort "overall recovery Stop Record terminal state drift" unless overall_recovery_stop["recovery_operation_state"] == "TERMINAL_STOPPED_HIDDEN_OFFSITE_RESTORE_MISMATCH"
  hidden_stop_evidence = overall_recovery_stop.fetch("decisive_non_pass_evidence")
  abort "overall recovery Stop Record public receipt locator drift" unless hidden_stop_evidence["public_aggregate_receipt_path"] == hidden_public_receipt_path && hidden_stop_evidence["public_aggregate_receipt_sha256"] == hidden_public_receipt_sha
  abort "overall recovery Stop Record restore status drift" unless hidden_stop_evidence["restore_verification"] == "NON_PASS_AGGREGATE_RESTORE_MISMATCH" && hidden_stop_evidence["pass_receipt_generated"] == false && hidden_stop_evidence["retry_count"] == 0
  abort "overall recovery Stop Record hidden access claim drift" unless hidden_stop_evidence["hidden_details_accessed_by_primary_agent"] == false

  hidden_custody = pilot_history.fetch("hidden_custody")
  abort "hidden custody quarantine state drift" unless hidden_custody["status"] == "QUARANTINED_HISTORICAL_RISK"
  abort "hidden public receipt locator drift" unless hidden_custody["public_receipt_path"] == hidden_public_receipt_path && hidden_custody["public_receipt_sha256"] == hidden_public_receipt_sha
  abort "hidden custody became a PASS" unless hidden_custody["restore_verification"] == "NON_PASS_AGGREGATE_RESTORE_MISMATCH" && hidden_custody["pass_receipt_generated"] == false && hidden_custody["retry_count"] == 0
  abort "primary Agent hidden access was authorized" unless hidden_custody["hidden_contents_or_paths_authorized_for_primary_agent"] == false
  abort "generic custodian artifact-name observation was erased" unless hidden_custody["generic_custodian_artifact_names_observed"] == true
  abort "hidden dataset identity or content access was falsely recorded" unless hidden_custody["hidden_dataset_identity_or_content_accessed"] == false
  abort "hidden private file content access was falsely recorded" unless hidden_custody["hidden_private_file_contents_read"] == false

  cutover = pilot_history.fetch("canonical_cutover")
  abort "P1-003 canonical cutover repository drift" unless cutover["repository"] == "/Users/lijunpeng/Developer/SourceLens-AIOS"
  abort "P1-003 canonical cutover parent drift" unless cutover["parent_commit"] == "65157b6f771c3a95486144ab712c3a99f9d06845" && cutover["parent_tree"] == "2409b9abacb276a0e977b65f6dcb0d1bdb6f1d30"
  abort "old Desktop repository remains canonical" unless cutover["old_desktop_repository_is_canonical"] == false
  abort "new canonical Task branch count drift" unless cutover["new_canonical_task_branch_count"] == 0
  abort "new canonical worktree count drift" unless cutover["new_canonical_worktree_count"] == 1
  abort "old Desktop cleanup policy drift" unless cutover["old_desktop_cleanup_policy"] == "REMOVE_ONLY_AFTER_ALL_CUTOVER_CHECKS_PASS"

  p1_004_authorization = JSON.parse(File.binread(p1_004_authorization_path))
  p1_004_stop = JSON.parse(File.binread(p1_004_terminal_paths.fetch("stop").first))
  p1_004_manifest = JSON.parse(File.binread(p1_004_terminal_paths.fetch("manifest").first))
  p1_004_seal = JSON.parse(File.binread(p1_004_terminal_paths.fetch("seal").first))
  p1_004_cto = JSON.parse(File.binread(p1_004_terminal_paths.fetch("cto").first))
  p1_004_security = JSON.parse(File.binread(p1_004_terminal_paths.fetch("security").first))
  p1_004_quality = JSON.parse(File.binread(p1_004_terminal_paths.fetch("quality").first))
  p1_004_restore = JSON.parse(File.binread(p1_004_restore_receipt_path))
  p1_004_id = "AIOS-P1-004_PARAMETERIZED_EVALUATION_HARNESS_ADMISSION"
  p1_004_state = "TERMINAL_STOPPED_AFTER_UNAUTHORIZED_TRANSIENT_EFFECT_AND_INDEPENDENT_REVIEW_FAIL"

  abort "P1-004 Task id drift" unless p1_004_task["task_id"] == p1_004_id && p1_004_task["phase"] == "P1"
  abort "P1-004 frozen Contract self-authorized" unless p1_004_task["status"] == "FOUNDER_EXECUTION_AUTHORIZATION_REQUIRED" && p1_004_task["execution_authorized"] == false
  abort "P1-004 Goal binding drift" unless p1_004_task.dig("authority_binding", "long_term_goal_canonical_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "P1-004 source parent drift" unless p1_004_task.dig("source", "activation_parent_commit") == "48258805dfa5e7a9c6d04d23e699b1a4e7b56a33" && p1_004_task.dig("source", "activation_parent_tree") == "46c9540905db8d9bf3157929ecb45bf294352fd4"
  abort "P1-004 network/provider/Secret boundary widened" unless p1_004_task.dig("environment", "network") == "forbidden" && p1_004_task.dig("environment", "provider") == "forbidden" && p1_004_task.dig("environment", "secrets") == "forbidden"
  abort "P1-004 external effects boundary widened" unless p1_004_task.dig("environment", "remote_effects") == "forbidden" && p1_004_task.dig("environment", "production_effects") == "forbidden" && p1_004_task.dig("environment", "public_release") == "forbidden"
  abort "P1-004 retry boundary widened" unless p1_004_task.dig("budget", "measurement_retries") == 0 && p1_004_task.dig("delegated_execution", "retry_or_successor_task") == "forbidden"
  abort "P1-004 capture-time authorization drift" unless p1_004_authorization["status"] == "AUTHORIZED_ACTIVE" && p1_004_authorization["task_id"] == p1_004_id
  abort "P1-004 authorization Contract drift" unless p1_004_authorization.dig("task_contract", "sha256") == p1_004_task_sha
  abort "P1-004 authorization Goal drift" unless p1_004_authorization.dig("authority", "goal_canonical_sha256") == "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0"
  abort "P1-004 authorization nonce drift" unless p1_004_authorization["consumed_single_use_nonce"] == "0de2abda5280156daa0dcdce4f71109d6be6df280c06debee7df72c9171282c5"
  abort "P1-004 automatic continuation was enabled" unless p1_004_authorization["automatic_main_advance"] == false && p1_004_authorization["automatic_next_task"] == false
  abort "P1-004 later scope was authorized" unless p1_004_authorization["b0_b1_b2_authorized"] == false && p1_004_authorization["p2_p3_authorized"] == false

  abort "P1-004 terminal state drift" unless p1_004_stop["task_id"] == p1_004_id && p1_004_stop["task_state"] == p1_004_state
  abort "P1-004 terminal reason drift" unless p1_004_stop.dig("failure", "reason_code") == "UNAUTHORIZED_TRANSIENT_EFFECT" && p1_004_stop.dig("failure", "contract_effect") == "STOP_TASK"
  abort "P1-004 nonce was not retired" unless p1_004_stop.dig("nonce_state", "status") == "RETIRED_AFTER_TASK_STOP"
  abort "P1-004 candidate was accepted" unless p1_004_stop.dig("worker_candidate", "accepted") == false
  abort "P1-004 Founder Gate was reached" unless p1_004_stop.dig("founder_gate", "status") == "NOT_REACHED" && p1_004_stop.dig("founder_gate", "eligible") == false
  abort "P1-004 Worker identity drift" unless p1_004_stop.dig("worker_candidate", "commit") == "68cf892d99ff636449f2694f7c7d5561e8693259" && p1_004_stop.dig("worker_candidate", "tree") == "4fd7b9bae834d1402029c16e076a78f1612abf08"
  abort "P1-004 Integration diff drift" unless p1_004_stop.dig("integration_state", "dirty_diff", "sha256") == "801261e297b03a299c01780367642e57a6cd9d1de43c46cb88c20531b46b6b36" && p1_004_stop.dig("integration_state", "dirty_diff", "byte_length") == 18_639
  abort "P1-004 CTO terminal verdict drift" unless p1_004_cto["verdict"] == "FAIL" && p1_004_cto["stop_effect"] == "STOP_TASK_TRIGGERED"
  abort "P1-004 Security terminal verdict drift" unless p1_004_security.dig("verdict", "result") == "FAIL" && p1_004_security.dig("verdict", "required_task_effect") == "STOP_TASK"
  abort "P1-004 Quality terminal verdict drift" unless p1_004_quality["verdict"] == "FAIL" && p1_004_quality["stop_effect"] == "STOP_TASK_TRIGGERED"

  p1_004_artifacts = p1_004_manifest.fetch("artifacts")
  abort "P1-004 terminal artifact population drift" unless p1_004_manifest["artifact_count"] == 12 && p1_004_artifacts.length == 12
  abort "P1-004 terminal artifact paths are not unique" unless p1_004_artifacts.map { |entry| entry.fetch("path") }.uniq.length == 12
  manifest_root_bytes = p1_004_artifacts.sort_by { |entry| entry.fetch("path") }.map { |entry| "#{entry.fetch("path")}\0#{entry.fetch("sha256")}\0#{entry.fetch("byte_length")}\n" }.join
  abort "P1-004 terminal manifest root drift" unless Digest::SHA256.hexdigest(manifest_root_bytes) == "f2d40a99178fe0b1dff221b1b5b0e85116aafe357d93bb028b676ca8185e530c" && p1_004_manifest["root_sha256"] == "f2d40a99178fe0b1dff221b1b5b0e85116aafe357d93bb028b676ca8185e530c"
  abort "P1-004 terminal Seal state drift" unless p1_004_seal["task_id"] == p1_004_id && p1_004_seal["task_state"] == p1_004_state
  abort "P1-004 terminal Seal stop binding drift" unless p1_004_seal.dig("terminal_stop_record", "sha256") == "ba3a50a97fe3bfd79c2568c13108828326dbba820cd2eef53e38fc54cd0bced3"
  abort "P1-004 terminal Seal manifest binding drift" unless p1_004_seal.dig("terminal_evidence_manifest", "sha256") == "201bcf229c3179f882a066173401c3b335c7dc36fea1828fc43d7cda6b7a9320" && p1_004_seal.dig("terminal_evidence_manifest", "root_sha256") == "f2d40a99178fe0b1dff221b1b5b0e85116aafe357d93bb028b676ca8185e530c"
  abort "P1-004 terminal Seal review binding drift" unless p1_004_seal["review_sha256"] == {"cto" => "aa0c9a359e8ea19f93ff855691f031dd4a3c044aa3257af8470691181c9a9513", "quality" => "06d512c7011422c7325d09ba9372aba55d74b6706a94232571ba29b9ecf5f0b9", "security" => "48bc8aa79a7f3eb2ad28077294339d8b5f3d90de4124354badbe528d54eff5b7"}

  abort "P1-004 restore verification is not PASS" unless p1_004_restore["result"] == "PASS"
  abort "P1-004 offsite locator drift" unless p1_004_restore.dig("offsite", "package_path") == "/Volumes/lijp/SourceLens-AIOS-P1-004-terminal-20260716T041834Z" && p1_004_restore.dig("offsite", "volume_uuid") == "2D3D7BCD-5BC5-3D2A-B853-F1FA95D290F8"
  abort "P1-004 bundle verification drift" unless p1_004_restore.dig("bundle", "sha256") == "5410da4d31bfc6deb003464eacc34b14b1a483f02bc4438a78a6c804685409ec" && p1_004_restore.dig("bundle", "verify") == "PASS" && p1_004_restore.dig("bundle", "complete_history") == true
  abort "P1-004 package root drift" unless p1_004_restore.dig("package", "payload_manifest_sha256") == "9f297dde6edc670dbc3924f98040520117f30594947ca05d81bed400dfa9fa01" && p1_004_restore.dig("package", "payload_root_sha256") == "ffa1be1609516c465c2529b25cd8f2fc001bf10168eb86f7330c3174bfd0987b"
  abort "P1-004 restored terminal Evidence drift" unless p1_004_restore.dig("terminal_evidence", "restored_artifacts") == "12/12" && p1_004_restore.dig("terminal_evidence", "manifest_root_sha256") == "f2d40a99178fe0b1dff221b1b5b0e85116aafe357d93bb028b676ca8185e530c"
  abort "P1-004 replayed Integration diff drift" unless p1_004_restore.dig("integration_uncommitted_delta", "replay_status") == "PASS" && p1_004_restore.dig("integration_uncommitted_delta", "sha256") == "801261e297b03a299c01780367642e57a6cd9d1de43c46cb88c20531b46b6b36"
  abort "P1-004 candidate acceptance was widened" unless p1_004_restore.dig("claim_boundary", "candidate_accepted") == false && p1_004_restore.dig("claim_boundary", "p1_004_capability_claims") == 0

  p1_004_history = truth.dig("task_history", "aios_p1_004")
  abort "P1-004 terminal history missing" unless p1_004_history.is_a?(Hash)
  expected_p1_004_history = {
    "task_id" => p1_004_id,
    "contract" => p1_004_task_path,
    "task_contract_sha256" => p1_004_task_sha,
    "status" => p1_004_state,
    "execution_authorized" => false,
    "original_execution_authorization_status" => "CONSUMED_AND_TERMINATED",
    "execution_authorization_sha256" => p1_004_authorization_sha,
    "execution_nonce_status" => "RETIRED_AFTER_TASK_STOP",
    "measurement_retries" => 0,
    "capability_claims" => 0,
    "founder_gate_status" => "NOT_REACHED",
    "main_advanced" => false,
    "resume_retry_successor_allowed" => false,
    "terminal_reason" => "UNAUTHORIZED_TRANSIENT_EFFECT"
  }
  expected_p1_004_history.each { |field, expected| abort "P1-004 terminal history drift: #{field}" unless p1_004_history[field] == expected }
  abort "P1-004 activation history drift" unless p1_004_history["activation"] == {"parent_commit" => "48258805dfa5e7a9c6d04d23e699b1a4e7b56a33", "parent_tree" => "46c9540905db8d9bf3157929ecb45bf294352fd4", "commit" => "ade80fca9ce4bd46446c0bf9e6e37fbde1e4dd0e", "tree" => "7d46a79ae09175e8d5e9a1b40b0b58be6467b550", "receipt_sha256" => "1fbbe9ae9a73581d739efdb392fca46c9e34ce66ef07161a74ee8f8545029ccb", "pre_execution_evidence_index_sha256" => "24929cd7fe456ec9e5ae6bd42f8768ab64cf20a7401e8dfd337b9a18741548de"}
  abort "P1-004 Worker history drift" unless p1_004_history["worker_candidate"] == {"commit" => "68cf892d99ff636449f2694f7c7d5561e8693259", "tree" => "4fd7b9bae834d1402029c16e076a78f1612abf08", "evidence_manifest_sha256" => "75c3f4d57949375dd96d49cc4cbbf3338dc5cee8cb1fda042135295272e70bc5", "accepted" => false}
  p1_004_cleanup = p1_004_history.fetch("terminal_cleanup")
  abort "P1-004 cleanup restore status drift" unless p1_004_cleanup["restore_status"] == "PASS"
  abort "P1-004 cleanup receipt drift" unless p1_004_cleanup["restore_verification_receipt_path"] == p1_004_restore_receipt_path && p1_004_cleanup["restore_verification_receipt_sha256"] == p1_004_restore_receipt_sha
  abort "P1-004 cleanup package drift" unless p1_004_cleanup["git_bundle_sha256"] == "5410da4d31bfc6deb003464eacc34b14b1a483f02bc4438a78a6c804685409ec" && p1_004_cleanup["payload_root_sha256"] == "ffa1be1609516c465c2529b25cd8f2fc001bf10168eb86f7330c3174bfd0987b"
  abort "P1-004 resource cleanup incomplete" unless p1_004_cleanup["task_branch_removed"] == true && p1_004_cleanup["task_worktree_removed"] == true

  completed = truth.dig("task_history", "aios_p1_001")
  abort "P1-001 completion history missing" unless completed.is_a?(Hash)
  expected_completion = {
    "task_id" => "AIOS-P1-001",
    "contract" => "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml",
    "task_contract_sha256" => "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f",
    "status" => "FOUNDER_GATE_ACCEPTED_COMPLETE",
    "execution_authorized" => false,
    "persistent_evidence_runs" => 1,
    "measurement_retries" => 0,
    "capability_claims" => 0,
    "accepted_candidate_commit" => "02342da942e291eaa65230f824fcf47eae8f8a30",
    "accepted_candidate_tree" => "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc",
    "evidence_manifest_sha256" => "e1f735816c18ab7631fa1d0b771deccc25564074350d1d74e67975d187ef3952",
    "cto_review" => "PASS",
    "security_review" => "PASS",
    "quality_review" => "PASS",
    "founder_gate_decision" => "PASS"
  }
  expected_completion.each do |field, expected|
    abort "P1-001 completion drift: #{field}" unless completed[field] == expected
  end
  gate_record = completed.fetch("founder_gate_decision_record")
  abort "Founder Gate record path drift" unless gate_record["path"] == "/Users/lijunpeng/Desktop/cc/project/.sourcelens-audit/p1-001-founder-gate-20260715T093331Z/FOUNDER_GATE_DECISION_RECORD.json"
  abort "Founder Gate record hash drift" unless gate_record["sha256"] == "2bacd875f90619ccba19a2cc56a257721ab85b76bd8d3bc168dc50acec4deb72"

  authorization = completed.fetch("execution_authorization_history")
  expected_authorization = {
    "authority" => "Human Founder",
    "authorization_model" => "TASK_LEVEL_DELEGATED_EXECUTION",
    "original_status" => "ACTIVE",
    "current_status" => "CONSUMED_AND_CLOSED_BY_FOUNDER_GATE",
    "source" => "CODEX_THREAD_FOUNDER_MESSAGE",
    "task_id" => "AIOS-P1-001",
    "task_contract_sha256" => "d2974752b088ff30b0764d6b482e19ea939cd497eb2db3e26af28bf09dc2e12f",
    "goal_body_canonical_sha256" => "fed643624aa5794a5cea5db2a04f25cc89d829a619e905df946a3616f14ad6c0",
    "authorized_parent_commit" => "12aa712c8e8456bb4d70a6b5014fb0937ada778f",
    "authorized_parent_tree" => "a2d966ebbd7784d30e7e38eaac04e0b8eb295022",
    "scope" => "TRUTH_SYNC_AND_P1_001_IMPLEMENTATION",
    "network" => "forbidden",
    "provider" => "forbidden",
    "secrets" => "forbidden",
    "remote" => "forbidden",
    "production" => "forbidden",
    "main_advance" => "forbidden_without_founder_gate",
    "binding_rule" => "SHA256_OF_ORDERED_LF_FIELDS_WITH_FINAL_LF"
  }
  expected_authorization.each do |field, expected|
    abort "Founder authorization drift: #{field}" unless authorization[field] == expected
  end
  authorization_fields = [
    "authority=#{authorization.fetch("authority").tr(" ", "_")}",
    "authorization_model=#{authorization.fetch("authorization_model")}",
    "task_id=#{authorization.fetch("task_id")}",
    "task_contract_sha256=#{authorization.fetch("task_contract_sha256")}",
    "goal_body_canonical_sha256=#{authorization.fetch("goal_body_canonical_sha256")}",
    "authorized_parent_commit=#{authorization.fetch("authorized_parent_commit")}",
    "authorized_parent_tree=#{authorization.fetch("authorized_parent_tree")}",
    "scope=#{authorization.fetch("scope")}",
    "network=#{authorization.fetch("network")}",
    "provider=#{authorization.fetch("provider")}",
    "secrets=#{authorization.fetch("secrets")}",
    "remote=#{authorization.fetch("remote")}",
    "production=#{authorization.fetch("production")}",
    "main_advance=#{authorization.fetch("main_advance")}",
  ]
  expected_binding = Digest::SHA256.hexdigest(authorization_fields.join("\n") + "\n")
  abort "Founder authorization binding drift" unless authorization["binding_sha256"] == expected_binding

  gate_history = truth.fetch("gate_history")
  abort "Founder Gate history population drift" unless gate_history.is_a?(Array) && gate_history.length == 1
  gate = gate_history.first
  abort "Founder Gate task drift" unless gate["task_id"] == "AIOS-P1-001"
  abort "Founder Gate decision drift" unless gate["gate"] == "FOUNDER_GATE" && gate["decision"] == "PASS"
  abort "Founder Gate record binding drift" unless gate["decision_record_sha256"] == "2bacd875f90619ccba19a2cc56a257721ab85b76bd8d3bc168dc50acec4deb72"
  abort "Founder Gate candidate drift" unless gate["candidate_commit"] == "02342da942e291eaa65230f824fcf47eae8f8a30" && gate["candidate_tree"] == "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc"
  abort "Founder Gate Evidence drift" unless gate["evidence_manifest_sha256"] == "e1f735816c18ab7631fa1d0b771deccc25564074350d1d74e67975d187ef3952"
  abort "Founder Gate claim boundary drift" unless gate["claim_boundary"] == "VISIBLE_SYNTHETIC_DETERMINISTIC_HARNESS_STUB_CONFORMANCE_ONLY"
  abort "Founder Gate auto-authorized a next task" unless gate["next_task_authorized"] == false
  abort "Harness conformance status drift" unless truth.dig("claim_boundary", "evaluation_harness") == "IMPLEMENTED_AND_FOUNDER_GATE_ACCEPTED_CONFORMANCE_ONLY"
  abort "Harness conformance did not pass" unless truth.dig("claim_boundary", "harness_conformance") == "PASS"
  abort "B0 terminal claim boundary drift" unless truth.dig("claim_boundary", "b0_adapter_conformance") == "TERMINAL_STOPPED_NOT_ACCEPTED"
  abort "live B0 performance was prematurely claimed" unless truth.dig("claim_boundary", "b0_live_model_performance") == "UNKNOWN_NO_PROVIDER_RUNS"
  abort "offsite custody status drift" unless truth.dig("historical_lineages", "archive", "offsite_status") == "PASS_WITH_DECLARED_HISTORICAL_COUNT_LIMITATION"
  abort "offsite verification binding drift" unless truth.dig("historical_lineages", "archive", "offsite_verification_receipt_sha256") == "e45658d02dc21184cc5c79d5a2b052ce1b2e3885b342930a2e0fb536ba03a91f"
  abort "production readiness falsely claimed" unless truth.dig("claim_boundary", "production_ready") == false
  abort "Agent capability falsely claimed" unless truth.dig("claim_boundary", "trustworthy_software_engineering_agent_proven") == false
  abort "historical lineages reopened" unless truth.dig("historical_lineages", "continuation_allowed") == false
  closed_lineages = truth.dig("historical_lineages", "names") || []
  %w[PRE PRE_DISCOVERY BOUND_EXP MCF EXECUTION_CARRIER SUPERVISOR_AND_ROOT_CUSTODY].each do |lineage|
    abort "historical lineage missing from closed set: #{lineage}" unless closed_lineages.include?(lineage)
  end
  abort "historical lineage status drift" unless truth.dig("historical_lineages", "status") == "CLOSED_AND_EXCLUDED_FROM_DEFAULT_CONTEXT"

  terminal_history = truth.dig("task_history", "aios_p1_002")
  abort "P1-002 terminal history missing" unless terminal_history.is_a?(Hash)
  expected_terminal_history = {
    "task_id" => terminal_task_id,
    "contract" => terminal_task_path,
    "task_contract_sha256" => terminal_task_sha,
    "status" => "TERMINAL_STOPPED_AFTER_ONE_TIME_BOUNDED_REMEDIATION_NON_PASS",
    "execution_authorized" => false,
    "original_execution_authorization_status" => "CONSUMED_AND_TERMINATED",
    "implementation_attempts" => 2,
    "persistent_evidence_runs" => 2,
    "accepted_evidence_runs" => 0,
    "measurement_retries" => 0,
    "provider_calls" => 0,
    "capability_claims" => 0,
    "claim_boundary" => "OFFLINE_B0_ADAPTER_CONFORMANCE_ONLY",
    "founder_gate_status" => "NOT_REACHED",
    "main_advanced" => false,
    "terminal_reason" => "GOVERNANCE_TASK_BRANCH_CARDINALITY_NON_PASS"
  }
  expected_terminal_history.each do |field, expected|
    abort "P1-002 terminal history drift: #{field}" unless terminal_history[field] == expected
  end
  first_candidate = terminal_history.fetch("first_rejected_candidate")
  abort "first rejected candidate drift" unless first_candidate == {
    "commit" => "dbc77f25d56994a8ae6aa228570c1327ec59ebd6",
    "tree" => "6acb236ebf5d87c78dda39af003e229b93c3b469",
    "outcome" => "STOPPED_AFTER_INDEPENDENT_REVIEW_NON_PASS"
  }
  remediation_candidate = terminal_history.fetch("bounded_remediation_candidate")
  abort "bounded remediation candidate drift" unless remediation_candidate == {
    "commit" => "e7a665315dda01da699f91caf1dec09ecf75d2dc",
    "tree" => "3b9b0105877eda7a8b49fa21ed639c0ae8f2efaa",
    "outcome" => "TERMINAL_STOPPED_AFTER_ONE_TIME_BOUNDED_REMEDIATION_NON_PASS"
  }
  terminal_evidence = terminal_history.fetch("terminal_evidence")
  abort "P1-002 terminal stop binding drift" unless terminal_evidence["stop_record_sha256"] == "09f174f85a8d3e87602f09f24d495664d0ba41081baea68ba00757277cd51aef"
  abort "P1-002 terminal manifest binding drift" unless terminal_evidence["evidence_manifest_sha256"] == "ed832bb6ec9cd104a5005106efed5b0b8b23e73d4fd26625d4008a3d62e97759"
  cleanup = terminal_history.fetch("terminal_cleanup")
  abort "terminal cleanup authorization drift" unless cleanup["authorization_record_sha256"] == "465ff355ddd53519eb0fed041cacd50d5c99dfae95f3acdfe8b3f01bc4d1b632"
  abort "terminal bundle drift" unless cleanup["git_bundle_sha256"] == "985fad210f1e3c270c7526f4b5e263ea697a749ab905f188c0c6a85673e61554"
  abort "terminal bundle receipt drift" unless cleanup["git_bundle_custody_receipt_sha256"] == "904835d27eeb333836c32ec5f662f7aa5fe2bd889266482097a8f6ee3094d7dc"
  abort "terminal branch/worktree cleanup incomplete" unless cleanup["task_branches_removed"] == true && cleanup["task_worktrees_removed"] == true

  abort "terminal Task id drift" unless terminal_task["task_id"] == terminal_task_id
  abort "terminal Task phase drift" unless terminal_task["phase"] == "P1"
  abort "terminal Task Contract schema drift" unless terminal_task["schema_version"] == 2
  abort "terminal Task capture-time authorization drift" unless terminal_task["status"] == "EXECUTION_AUTHORIZED" && terminal_task["execution_authorized"] == true
  abort "terminal Task message binding drift" unless terminal_task.dig("founder_authorization", "message_sha256") == "bedd3c781cc224a13c3e64a7ff7bcd6d9d23cafaf6a897d70f4c3994697ec6db"
  abort "terminal Task parent drift" unless terminal_task.dig("source", "authorized_parent_commit") == "c3bbcf07b597220710fda1f7ee335d4b1ccbba5e" && terminal_task.dig("source", "authorized_parent_tree") == "b035d7410065f5f17b914365c10a3acc5f66fc6d"
  abort "terminal Task capture-time branch drift" unless terminal_task.dig("source", "task_branch") == "task/AIOS-P1-002-b0-adapter-conformance"
  abort "terminal Task live model boundary drift" unless terminal_task.dig("environment", "live_model_invocation") == "forbidden"
  abort "terminal Task Provider boundary drift" unless terminal_task.dig("environment", "provider_calls") == 0 && terminal_task.dig("budget", "provider_calls") == 0
  abort "terminal Task network boundary drift" unless terminal_task.dig("environment", "network") == "forbidden" && terminal_task.dig("budget", "network_calls") == 0
  abort "terminal Task tool boundary drift" unless terminal_task.dig("environment", "enabled_tools") == [] && terminal_task.dig("environment", "loop_limit") == 1
  abort "terminal Task retry boundary drift" unless terminal_task.dig("budget", "measurement_retries") == 0

  terminal_worker_paths = terminal_task.dig("implementation_scope", "worker_writable_paths") || []
  terminal_integration_paths = terminal_task.dig("implementation_scope", "integration_writable_paths") || []
  terminal_quality_paths = terminal_task.dig("implementation_scope", "quality_owned_preimplementation_paths") || []
  expected_terminal_worker_paths = [
    "evaluation-harness/adapters/b0_direct_model/**",
    "evaluation-harness/harness/b0_direct_model/**",
    "evaluation-harness/recording/b0-direct-model-offline-evidence/**",
    "evaluation-harness/recording/recorder.mjs"
  ]
  expected_terminal_integration_paths = ["scripts/verify-p1-b0-direct-model-offline.sh", "Makefile"]
  expected_terminal_quality_paths = [
    "evaluation-harness/fixtures/b0_direct_model/**",
    "evaluation-harness/evaluator/b0_direct_model/**"
  ]
  abort "terminal Worker paths drifted" unless terminal_worker_paths == expected_terminal_worker_paths
  abort "terminal Integration paths drifted" unless terminal_integration_paths == expected_terminal_integration_paths
  abort "terminal Quality paths drifted" unless terminal_quality_paths == expected_terminal_quality_paths
  terminal_owned = terminal_worker_paths + terminal_integration_paths + terminal_quality_paths
  abort "terminal owned path declaration overlap" unless terminal_owned.uniq.length == terminal_owned.length
  abort "terminal Task Contract became writable" if terminal_owned.include?(terminal_task_path)
  abort "accepted schemas became writable in terminal Task" if terminal_owned.any? { |path| path.start_with?("docs/aios/schemas/") }
  abort "terminal Task immutable binding missing" unless (terminal_task.dig("implementation_scope", "immutable_inputs") || []).include?(terminal_task_path)

  abort "task id drift" unless task["task_id"] == "AIOS-P1-001"
  abort "task phase drift" unless task["phase"] == "P1"
  abort "frozen Task Contract must not self-authorize execution" unless task["execution_authorized"] == false
  abort "frozen Task Contract capture-time status drift" unless task["status"] == "DRAFT_READY_FOR_FOUNDER_TASK_AUTHORIZATION"
  abort "harness stub missing" unless task.dig("baseline_plan", "harness_stub", "name") == "HARNESS_STUB"
  abort "harness stub included in VTSR" unless task.dig("baseline_plan", "harness_stub", "included_in_vtsr_denominator") == false
  %w[B0 B1 B2].each { |key| abort "future baseline missing: #{key}" unless task.dig("baseline_plan", "future_true_baselines", key) }
  abort "network enabled" unless task.dig("environment", "network") == "disabled"
  abort "provider enabled" unless task.dig("environment", "provider") == "none"
  abort "task worktree write boundary widened" unless task.dig("environment", "task_worktree_write") == "exact_owned_paths_only"
  abort "canonical main write enabled" unless task.dig("environment", "canonical_main_write") == "forbidden"
  abort "system-under-test write enabled" unless task.dig("environment", "system_under_test_checkout_write") == "forbidden"
  abort "measurement retry widened" unless task.dig("budget", "measurement_retries") == 0

  worker_paths = task.dig("implementation_scope", "worker_writable_paths") || []
  integration_paths = task.dig("implementation_scope", "integration_writable_paths") || []
  quality_paths = task.dig("implementation_scope", "quality_owned_preimplementation_paths") || []
  immutable_paths = task.dig("implementation_scope", "immutable_inputs") || []
  expected_worker_paths = [
    "evaluation-harness/harness/**",
    "evaluation-harness/adapters/harness_stub/**",
    "evaluation-harness/recording/**",
    "evaluation-harness/replay/**"
  ]
  expected_integration_paths = ["scripts/verify-p1-harness.sh", "Makefile"]
  expected_quality_paths = [
    "evaluation-harness/evaluator/**",
    "evaluation-harness/fixtures/visible/**",
    "evaluation-harness/fixtures/oracle/**"
  ]
  expected_immutable_paths = [
    "docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml",
    "docs/aios/schemas/task-spec.schema.json",
    "docs/aios/schemas/environment-snapshot.schema.json",
    "docs/aios/schemas/system-configuration.schema.json",
    "docs/aios/schemas/run-record.schema.json",
    "docs/aios/EVALUATION_PROTOCOL.md",
    "docs/aios/BASELINE_ADAPTER_CONTRACT.md"
  ]
  abort "Worker write paths drifted" unless worker_paths == expected_worker_paths
  abort "Integration write paths drifted" unless integration_paths == expected_integration_paths
  abort "Quality write paths drifted" unless quality_paths == expected_quality_paths
  abort "immutable input set drifted" unless immutable_paths == expected_immutable_paths
  all_owned = worker_paths + integration_paths + quality_paths
  abort "owned write paths overlap" unless all_owned.uniq.length == all_owned.length
  abort "Task Contract became writable" if all_owned.include?("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml")
  abort "accepted schemas became writable" if all_owned.any? { |path| path.start_with?("docs/aios/schemas/") }
  abort "Task Contract is not immutable" unless immutable_paths.include?("docs/aios/tasks/P1-001_EVALUATION_HARNESS.yaml")
  abort "accepted schema set incomplete" unless %w[task-spec environment-snapshot system-configuration run-record].all? { |name| immutable_paths.include?("docs/aios/schemas/#{name}.schema.json") }
  abort "Quality evaluator ownership missing" unless quality_paths.include?("evaluation-harness/evaluator/**")
  abort "Quality visible fixture ownership missing" unless quality_paths.include?("evaluation-harness/fixtures/visible/**")
  abort "Quality oracle ownership missing" unless quality_paths.include?("evaluation-harness/fixtures/oracle/**")
  abort "Worker can modify visible fixture" if worker_paths.include?("evaluation-harness/fixtures/visible/**")

  abort "migration ledger became current authority" unless ledger["current_phase_authority"] == false
  ids = ledger.fetch("assets").map { |entry| entry.fetch("id") }
  abort "duplicate asset ids" unless ids.uniq.length == ids.length
  %w[EVALUATION_HARNESS JAVA_AST_AND_CODE_GRAPH CODE_CHUNKS_SEARCH_AND_RETRIEVAL AGENT_RUNTIME MULTI_AGENT_ORGANIZATION_RUNTIME].each do |id|
    abort "required disposition missing: #{id}" unless ids.include?(id)
  end

  Dir.glob("docs/aios/schemas/*.json").each { |path| JSON.parse(File.read(path)) }
' || fail "structured authority validation failed"

[[ "$(git rev-parse 02342da942e291eaa65230f824fcf47eae8f8a30^{tree})" == "1a31751dc1b4d5bc2c9b2c4aaf0aa640528edecc" ]] || fail "accepted candidate tree no longer resolves"
git merge-base --is-ancestor 02342da942e291eaa65230f824fcf47eae8f8a30 HEAD || fail "accepted candidate is not an ancestor of current main"

historical_paths=(
  CHAIRMAN_BRIEFING.md
  docs/AGENT_ACTIVITY_LOG.md
  docs/AGENT_DECISION_REGISTER.md
  docs/AGENT_STATUS_BOARD.md
  docs/CODEX_HANDOFF.md
  docs/PROJECT_PLAN.md
  docs/PHASE_REQUIREMENTS.md
  docs/PRODUCT_PROGRESS_LOG.md
  docs/REFACTOR_ROADMAP.md
  docs/TEAM_OPERATING_MODEL.md
  docs/SOURCELENS_OPERATING_SYSTEM.md
  docs/aios/CODEX_MASTER_PROMPT.md
  docs/aios/P0_GATE.md
  docs/aios/P0_INDEPENDENT_REVIEW.md
)

for path in "${historical_paths[@]}"; do
  [[ ! -e "$path" ]] || fail "historical path leaked into active tree: $path"
done

if git grep -n -E 'AIOS-P1-001 Contract Freeze|P1-001 execution: NOT AUTHORIZED' -- web-console/src >/dev/null 2>&1; then
  fail "product UI mirrors project control-plane state"
fi

task_branches="$(git for-each-ref --format='%(refname:short)' refs/heads/task/)"
task_branch_count="$(printf '%s\n' "$task_branches" | grep -c . || true)"
worktree_paths="$(git worktree list --porcelain | sed -n 's/^worktree //p')"
worktree_count="$(printf '%s\n' "$worktree_paths" | grep -c . || true)"
expected_task_branch="task/AIOS-P1-005-evaluation-matrix-vtsr-validator"
expected_task_worktree="/Users/lijunpeng/Developer/.sourcelens-worktrees/AIOS-P1-005-evaluation-matrix-vtsr-validator"
activation_receipt="/Users/lijunpeng/Developer/.sourcelens-audit/p1-005-evaluation-matrix-vtsr-execution-20260716T051135Z/activation/ACTIVATION_RECEIPT.json"
terminal_stop_record="/Users/lijunpeng/Developer/.sourcelens-audit/p1-005-evaluation-matrix-vtsr-execution-20260716T051135Z/terminal/TERMINAL_STOP_RECORD.json"
if [[ -f "$terminal_stop_record" && "$task_branch_count" -eq 1 ]]; then
  [[ "$task_branches" == "$expected_task_branch" ]] || fail "terminal P1-005 Task branch population drift: $task_branches"
  [[ "$worktree_count" -eq 2 ]] || fail "terminal P1-005 pre-cleanup worktree population must be canonical plus one exact Task worktree"
  printf '%s\n' "$worktree_paths" | grep -Fx "$ROOT_DIR" >/dev/null || fail "canonical worktree missing"
  printf '%s\n' "$worktree_paths" | grep -Fx "$expected_task_worktree" >/dev/null || fail "exact P1-005 Task worktree missing"
elif [[ -f "$terminal_stop_record" ]]; then
  [[ "$task_branch_count" -eq 0 ]] || fail "unexpected Task branch remains after P1-005 terminal cleanup: $task_branches"
  [[ "$worktree_count" -eq 1 && "$worktree_paths" == "$ROOT_DIR" ]] || fail "post-cleanup worktree population is not exactly the canonical repository"
elif [[ -f "$activation_receipt" ]]; then
  fail "P1-005 activation exists without terminal stop record"
else
  [[ "$task_branch_count" -eq 0 ]] || fail "P1-005 Task branch exists before activation receipt: $task_branches"
  [[ "$worktree_count" -eq 1 && "$worktree_paths" == "$ROOT_DIR" ]] || fail "pre-resource worktree population is not exactly the canonical repository"
fi

p1_005_closure_parent="1354e6a401d3a9d7794ece9de6e5a438e13ad5e6"
p1_005_closure_paths_expected=$'docs/PROJECT_CODE_MAP.md\ndocs/aios/truth/project_state.yaml\nscripts/check-p1-safety-boundary.sh\nscripts/validate-aios-governance.sh'
current_head="$(git rev-parse HEAD)"
if [[ "$current_head" == "$p1_005_closure_parent" ]]; then
  p1_005_closure_paths_actual="$(git diff --name-only HEAD -- | LC_ALL=C sort)"
  [[ "$p1_005_closure_paths_actual" == "$p1_005_closure_paths_expected" ]] || fail "P1-005 terminal closure pre-commit path population drift"
else
  git merge-base --is-ancestor "$p1_005_closure_parent" "$current_head" || fail "P1-005 activation commit is not an ancestor of current main"
  p1_005_closure_commit="$(git rev-list --reverse --first-parent "$p1_005_closure_parent..$current_head" | sed -n '1p')"
  [[ -n "$p1_005_closure_commit" ]] || fail "P1-005 terminal closure commit cannot be located"
  [[ "$(git rev-list --parents -n 1 "$p1_005_closure_commit")" == "$p1_005_closure_commit $p1_005_closure_parent" ]] || fail "P1-005 terminal closure commit is not the unique direct child of the activation commit"
  [[ "$(git diff --name-only "$p1_005_closure_parent" "$p1_005_closure_commit" -- | LC_ALL=C sort)" == "$p1_005_closure_paths_expected" ]] || fail "P1-005 terminal closure commit path population drift"
  [[ "$(git log -1 --format=%s "$p1_005_closure_commit")" == "governance(p1): close terminal P1-005 state" ]] || fail "P1-005 terminal closure commit subject drift"
fi

closure_parent="ade80fca9ce4bd46446c0bf9e6e37fbde1e4dd0e"
closure_paths_expected=$'docs/PROJECT_CODE_MAP.md\ndocs/aios/truth/project_state.yaml\nscripts/check-p1-safety-boundary.sh\nscripts/validate-aios-governance.sh'
current_head="$(git rev-parse HEAD)"
if [[ "$current_head" == "$closure_parent" ]]; then
  closure_paths_actual="$(git diff --name-only HEAD -- | LC_ALL=C sort)"
  [[ "$closure_paths_actual" == "$closure_paths_expected" ]] || fail "P1-004 terminal closure pre-commit path population drift"
else
  git merge-base --is-ancestor "$closure_parent" "$current_head" || fail "P1-004 activation commit is not an ancestor of current main"
  closure_commit="$(git rev-list --reverse --first-parent "$closure_parent..$current_head" | sed -n '1p')"
  [[ -n "$closure_commit" ]] || fail "P1-004 terminal closure commit cannot be located"
  closure_parent_line="$(git rev-list --parents -n 1 "$closure_commit")"
  [[ "$closure_parent_line" == "$closure_commit $closure_parent" ]] || fail "P1-004 terminal closure commit is not the unique direct child of the activation commit"
  closure_paths_actual="$(git diff --name-only "$closure_parent" "$closure_commit" -- | LC_ALL=C sort)"
  [[ "$closure_paths_actual" == "$closure_paths_expected" ]] || fail "P1-004 terminal closure commit path population drift"
  [[ "$(git log -1 --format=%s "$closure_commit")" == "governance(p1): close terminal P1-004 state" ]] || fail "P1-004 terminal closure commit subject drift"
fi
if git cat-file -e 68cf892d99ff636449f2694f7c7d5561e8693259^{commit} 2>/dev/null; then
  ! git merge-base --is-ancestor 68cf892d99ff636449f2694f7c7d5561e8693259 "$current_head" || fail "rejected P1-004 Worker candidate entered canonical main"
fi

git diff --check || fail "git whitespace validation failed"

echo "AIOS governance validation passed."

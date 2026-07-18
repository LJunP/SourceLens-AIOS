#!/usr/bin/env bash
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
TRUTH_PATH="${ROOT_DIR}/docs/aios/truth/project_state.yaml"
RULES_PATH="${ROOT_DIR}/AGENTS.md"

fail() {
  echo "AIOS GOVERNANCE FAIL: $*" >&2
  exit 1
}

check_founder_knowledge_section() {
  local rules_path="$1"
  local section_header='## Founder Knowledge System（常驻规则）'
  local canonical_byte_length='1011'
  local canonical_sha256='e6b353038598122a9d347378ceaab1dc4e7957357bb29f72adfbcbf27820303e'

  ruby -rdigest -e '
    rules_path, header, expected_length, expected_sha = ARGV
    header = header.dup.force_encoding("UTF-8")
    abort "Founder Knowledge System rules file missing" unless File.file?(rules_path) && !File.symlink?(rules_path)
    bytes = File.binread(rules_path)
    rules = bytes.dup.force_encoding("UTF-8")
    abort "Founder Knowledge System document encoding invalid" unless rules.valid_encoding?
    lines = rules.lines
    starts = lines.each_index.select { |index| lines[index].sub(/\r?\n\z/, "") == header }
    abort "Founder Knowledge System exact section missing or duplicated" unless starts.length == 1
    start_index = starts.first
    end_index = ((start_index + 1)...lines.length).find { |index| lines[index].start_with?("## ") }
    abort "Founder Knowledge System must be the terminal H2 section" if end_index
    section = lines[start_index...lines.length].join
    canonical = section.gsub(/\r\n?/, "\n").sub(/\n*\z/, "") + "\n"
    abort "Founder Knowledge System exact section byte drift" unless
      canonical.bytesize == Integer(expected_length, 10) && Digest::SHA256.hexdigest(canonical) == expected_sha
  ' "$rules_path" "$section_header" "$canonical_byte_length" "$canonical_sha256" \
    || fail "Founder Knowledge System exact section drift"
}

check_authority_bindings() {
  ruby -ryaml -rdigest -rpathname -e '
    repo_root = Pathname.new(ARGV.fetch(0)).realpath
    truth_path = Pathname.new(ARGV.fetch(1))
    abort "Truth missing or symlinked" unless truth_path.file? && !truth_path.symlink?
    truth = YAML.safe_load(truth_path.read, permitted_classes: [], permitted_symbols: [], aliases: false)
    abort "Truth must be a mapping" unless truth.is_a?(Hash)
    authority = truth["authority"]
    abort "authority mapping missing" unless authority.is_a?(Hash)

    expected = {
      "strategy" => "docs/aios/STRATEGIC_CONSTITUTION.md",
      "execution_protocol" => "docs/aios/MASTER_EXECUTION_PROTOCOL.md",
      "founder_delegation_policy" => "docs/aios/FOUNDER_DELEGATION_POLICY.md",
      "evaluation_protocol" => "docs/aios/EVALUATION_PROTOCOL.md"
    }
    expected.each do |key, expected_path|
      binding = authority[key]
      abort "#{key} authority binding missing" unless binding.is_a?(Hash)
      path = binding["path"]
      digest = binding["sha256"]
      abort "#{key} authority path drift" unless path == expected_path
      abort "#{key} authority SHA-256 invalid" unless digest.is_a?(String) && digest.match?(/\A[0-9a-f]{64}\z/)
      relative = Pathname.new(path)
      abort "#{key} authority path must be repository-relative" if relative.absolute? || relative.each_filename.any? { |part| part == ".." }
      candidate = repo_root.join(relative).cleanpath
      abort "#{key} authority file missing or symlinked" unless candidate.file? && !candidate.symlink?
      real_candidate = candidate.realpath
      prefix = repo_root.to_s + File::SEPARATOR
      abort "#{key} authority path escaped repository" unless real_candidate.to_s.start_with?(prefix)
      abort "#{key} authority hash drift" unless Digest::SHA256.file(real_candidate).hexdigest == digest
      abort "#{key} authority status missing" unless binding["status"].is_a?(String) && !binding["status"].empty?
    end

    abort "Truth current_facts path drift" unless authority["current_facts"] == "docs/aios/truth/project_state.yaml"
    route = truth["current_phase_route"]
    abort "current_phase_route missing" unless route.is_a?(Hash)
    route_policy = route["policy"]
    founder_policy = authority["founder_delegation_policy"]
    abort "route policy binding missing" unless route_policy.is_a?(Hash)
    abort "route policy path/hash drift" unless
      route_policy["path"] == founder_policy["path"] &&
      route_policy["sha256"] == founder_policy["sha256"] &&
      route_policy["version"] == founder_policy["version"]
  ' "$ROOT_DIR" "$TRUTH_PATH" || fail "current authority file binding invalid"
}

command -v ruby >/dev/null 2>&1 || fail "ruby is required"

if [[ $# -gt 0 ]]; then
  [[ $# -eq 2 && "$1" == "--check-founder-knowledge-section" ]] \
    || fail "unsupported arguments"
  check_founder_knowledge_section "$2"
  echo "Founder Knowledge System exact section validation passed."
  exit 0
fi

required_files=(
  AGENTS.md
  docs/aios/truth/project_state.yaml
  docs/aios/STRATEGIC_CONSTITUTION.md
  docs/aios/MASTER_EXECUTION_PROTOCOL.md
  docs/aios/FOUNDER_DELEGATION_POLICY.md
  docs/aios/EVALUATION_PROTOCOL.md
  scripts/validate-current-task-authority.rb
  scripts/test-current-task-authority.rb
)
for relative_path in "${required_files[@]}"; do
  [[ -f "${ROOT_DIR}/${relative_path}" && ! -L "${ROOT_DIR}/${relative_path}" ]] \
    || fail "required current-authority file missing, non-regular, or symlinked: ${relative_path}"
done

boundary_markers=(
  '一个长期 Goal、一个当前 Phase、一条关键路径、一个当前 Task。'
  '继承的旧 SourceLens 工作区只读，不得修改、暂存、stash、reset、clean 或删除。'
  'Task Contract、Truth 与 validator 必须数据驱动'
  'P1 不建设 Supervisor、Root Custody、完整 Trust Runtime、强隔离平台或 Multi-Agent Runtime。'
  '/Users/lijunpeng/Documents/AIOS-Founder-Knowledge-Vault'
  '它不是 Truth、Git source of truth、Evidence Store、Task authority/control plane、Gate authority/decision system 或能力证明'
  '独立 Knowledge Reviewer'
  'exact Artifact bytes PASS'
  'FACT`、`INFERENCE`、`UNKNOWN'
  '不得阻断后续工程开发'
  '禁止删除或覆盖任何历史 Artifact'
)
for marker in "${boundary_markers[@]}"; do
  grep -Fq -- "$marker" "$RULES_PATH" || fail "required AGENTS boundary marker missing: ${marker}"
done

check_founder_knowledge_section "$RULES_PATH"
check_authority_bindings
ruby "${ROOT_DIR}/scripts/validate-current-task-authority.rb"

echo "AIOS current governance validation passed (data-driven current authority only)."

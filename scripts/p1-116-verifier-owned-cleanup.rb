#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "json"
require "securerandom"

SCHEMA = "p1-116-verifier-owned-cleanup-ledger/v1"

class CleanupNonPass < StandardError
  attr_reader :code

  def initialize(code, message)
    @code = code
    super("#{code}: #{message}")
  end
end

def fail_closed(code, message)
  raise CleanupNonPass.new(code, message)
end

def relative_path(root, path)
  return "." if path == root

  prefix = "#{root}/"
  fail_closed("PATH_OUTSIDE_ROOT", path) unless path.start_with?(prefix)

  path.delete_prefix(prefix)
end

def object_record(root, path)
  stat = File.lstat(path)
  record = {
    "path" => relative_path(root, path),
    "dev" => stat.dev,
    "ino" => stat.ino,
    "uid" => stat.uid,
    "gid" => stat.gid,
    "mode" => stat.mode & 0o7777
  }

  if stat.directory?
    record["type"] = "DIRECTORY"
  elsif stat.file?
    bytes = File.binread(path)
    record["type"] = "REGULAR"
    record["byte_length"] = bytes.bytesize
    record["sha256"] = Digest::SHA256.hexdigest(bytes)
  elsif stat.symlink?
    target = File.readlink(path).b
    record["type"] = "SYMLINK"
    record["target_byte_length"] = target.bytesize
    record["target_sha256"] = Digest::SHA256.hexdigest(target)
  else
    fail_closed("UNSUPPORTED_OBJECT_TYPE", relative_path(root, path))
  end

  record
end

def inventory(root)
  root = File.expand_path(root)
  root_stat = File.lstat(root)
  fail_closed("ROOT_TYPE_INVALID", root) unless root_stat.directory? && !root_stat.symlink?

  records = []
  walk = lambda do |path|
    record = object_record(root, path)
    records << record
    return unless record.fetch("type") == "DIRECTORY"

    Dir.children(path).sort.each do |name|
      walk.call(File.join(path, name))
    end
  end
  walk.call(root)
  records.sort_by { |record| record.fetch("path").b }
end

def assert_exact_record(expected, actual)
  return if expected == actual

  path = expected["path"] || actual["path"] || "UNKNOWN"
  fail_closed(
    "OBJECT_IDENTITY_DRIFT",
    "#{path} expected=#{JSON.generate(expected)} actual=#{JSON.generate(actual)}"
  )
end

def capture(root, expected_root)
  root = File.expand_path(root)
  records = inventory(root)
  actual_root = records.find { |record| record.fetch("path") == "." }
  fail_closed("ROOT_RECORD_MISSING", root) unless actual_root
  assert_exact_record(expected_root.merge("path" => ".", "type" => "DIRECTORY"), actual_root)

  {
    "schema_version" => SCHEMA,
    "root" => root,
    "ownership_boundary" => "SOLE_PRODUCER_EXIT_EXACT_HANDOFF",
    "records" => records
  }
end

def parse_ledger(bytes, root)
  ledger = JSON.parse(bytes)
  fail_closed("LEDGER_SCHEMA_INVALID", "schema") unless ledger["schema_version"] == SCHEMA
  fail_closed("LEDGER_ROOT_MISMATCH", ledger["root"].to_s) unless
    ledger["root"] == File.expand_path(root)
  records = ledger["records"]
  fail_closed("LEDGER_RECORDS_INVALID", "records") unless records.is_a?(Array) && !records.empty?

  paths = records.map { |record| record["path"] }
  fail_closed("LEDGER_PATH_DUPLICATE", paths.inspect) unless paths.uniq.length == paths.length
  fail_closed("LEDGER_ROOT_RECORD_INVALID", paths.inspect) unless paths.include?(".")
  ledger
rescue JSON::ParserError => error
  fail_closed("LEDGER_JSON_INVALID", error.message)
end

def path_for(root, relative)
  return root if relative == "."

  fail_closed("LEDGER_PATH_INVALID", relative.to_s) unless
    relative.is_a?(String) &&
    !relative.empty? &&
    !relative.start_with?("/") &&
    relative.split("/").none? { |part| part.empty? || part == "." || part == ".." }

  File.join(root, relative)
end

def verify_complete_tree!(root, records)
  actual = inventory(root)
  expected_by_path = records.to_h { |record| [record.fetch("path"), record] }
  actual_by_path = actual.to_h { |record| [record.fetch("path"), record] }
  fail_closed(
    "TREE_INVENTORY_DRIFT",
    "expected=#{expected_by_path.keys.sort.inspect} actual=#{actual_by_path.keys.sort.inspect}"
  ) unless expected_by_path.keys.sort == actual_by_path.keys.sort

  expected_by_path.each do |path, expected|
    assert_exact_record(expected, actual_by_path.fetch(path))
  end
end

def cleanup(root, ledger)
  root = File.expand_path(root)
  records = ledger.fetch("records")

  # Phase 1 is intentionally deletion-free. Any mismatch preserves the entire tree.
  verify_complete_tree!(root, records)

  ordered = records.sort_by do |record|
    path = record.fetch("path")
    [-path.count("/"), path == "." ? 1 : 0, path.b]
  end

  ordered.each do |expected|
    path = path_for(root, expected.fetch("path"))
    actual = object_record(root, path)
    assert_exact_record(expected, actual)
    case expected.fetch("type")
    when "REGULAR", "SYMLINK"
      File.unlink(path)
    when "DIRECTORY"
      Dir.rmdir(path)
    else
      fail_closed("LEDGER_TYPE_INVALID", expected.fetch("type").to_s)
    end
  end

  fail_closed("ROOT_CLEANUP_INCOMPLETE", root) if File.exist?(root) || File.symlink?(root)
  true
end

def root_identity(root)
  stat = File.lstat(root)
  {
    "dev" => stat.dev,
    "ino" => stat.ino,
    "uid" => stat.uid,
    "gid" => stat.gid,
    "mode" => stat.mode & 0o7777
  }
end

def unique_root(label)
  root = "/private/tmp/sourcelens-p1-116-cleanup-#{label}-#{Process.pid}-#{SecureRandom.hex(12)}"
  fail_closed("SELF_TEST_ROOT_PREEXISTS", root) if File.exist?(root) || File.symlink?(root)
  Dir.mkdir(root, 0o700)
  root
end

def safe_recapture_cleanup(root)
  return unless File.exist?(root) || File.symlink?(root)

  ledger = capture(root, root_identity(root))
  cleanup(root, ledger)
end

def expect_rejection(code)
  yield
  fail_closed("SELF_TEST_FALSE_ACCEPT", code)
rescue CleanupNonPass => error
  raise unless error.code == code
end

def populate_fixture(root)
  Dir.mkdir(File.join(root, "data"), 0o700)
  File.binwrite(File.join(root, "data", "value.txt"), "owned\n")
  File.chmod(0o600, File.join(root, "data", "value.txt"))
  File.symlink("data/value.txt", File.join(root, "value-link"))
end

def self_test_case(label)
  root = unique_root(label)
  populate_fixture(root)
  ledger = capture(root, root_identity(root))
  yield(root, ledger)
ensure
  safe_recapture_cleanup(root) if root && (File.exist?(root) || File.symlink?(root))
end

def run_self_test
  self_test_case("normal") do |root, ledger|
    cleanup(root, ledger)
  end

  self_test_case("unexpected") do |root, ledger|
    File.binwrite(File.join(root, "unexpected.txt"), "unexpected\n")
    expect_rejection("TREE_INVENTORY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.exist?(File.join(root, "data", "value.txt")) &&
      File.exist?(File.join(root, "unexpected.txt"))
  end

  self_test_case("missing") do |root, ledger|
    File.unlink(File.join(root, "data", "value.txt"))
    expect_rejection("TREE_INVENTORY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.directory?(File.join(root, "data")) &&
      File.symlink?(File.join(root, "value-link"))
  end

  self_test_case("content") do |root, ledger|
    File.binwrite(File.join(root, "data", "value.txt"), "drift\n")
    expect_rejection("OBJECT_IDENTITY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.binread(File.join(root, "data", "value.txt")) == "drift\n"
  end

  self_test_case("mode") do |root, ledger|
    File.chmod(0o640, File.join(root, "data", "value.txt"))
    expect_rejection("OBJECT_IDENTITY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.exist?(File.join(root, "data", "value.txt"))
  end

  self_test_case("file-type") do |root, ledger|
    path = File.join(root, "data", "value.txt")
    File.unlink(path)
    File.symlink("../value-link", path)
    expect_rejection("OBJECT_IDENTITY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless File.symlink?(path)
  end

  self_test_case("directory") do |root, ledger|
    path = File.join(root, "data")
    moved = File.join(root, "moved-data")
    File.rename(path, moved)
    Dir.mkdir(path, 0o700)
    expect_rejection("TREE_INVENTORY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.directory?(path) && File.directory?(moved)
  end

  self_test_case("symlink") do |root, ledger|
    path = File.join(root, "value-link")
    File.unlink(path)
    File.symlink("different-target", path)
    expect_rejection("OBJECT_IDENTITY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.readlink(path) == "different-target"
  end

  self_test_case("root") do |root, ledger|
    moved = "#{root}-moved"
    File.rename(root, moved)
    Dir.mkdir(root, 0o700)
    expect_rejection("TREE_INVENTORY_DRIFT") { cleanup(root, ledger) }
    fail_closed("SELF_TEST_MUTATED_ON_REJECT", root) unless
      File.directory?(root) && File.directory?(moved)
    safe_recapture_cleanup(moved)
  end

  puts JSON.generate(
    "status" => "PASS",
    "cases" => 9,
    "recursive_deletion_used" => false
  )
end

begin
  command = ARGV.shift
  case command
  when "capture"
    root = ARGV.fetch(0)
    expected = {
      "dev" => Integer(ARGV.fetch(1), 10),
      "ino" => Integer(ARGV.fetch(2), 10),
      "uid" => Integer(ARGV.fetch(3), 10),
      "gid" => Integer(ARGV.fetch(4), 10),
      "mode" => Integer(ARGV.fetch(5), 8)
    }
    puts JSON.generate(capture(root, expected))
  when "cleanup"
    root = ARGV.fetch(0)
    ledger = parse_ledger($stdin.binmode.read, root)
    cleanup(root, ledger)
    puts JSON.generate("status" => "PASS", "root_absent" => true)
  when "self-test"
    run_self_test
  else
    warn "usage: #{$PROGRAM_NAME} capture ROOT DEV INO UID GID MODE | cleanup ROOT | self-test"
    exit 64
  end
rescue CleanupNonPass => error
  warn error.message
  exit 1
end

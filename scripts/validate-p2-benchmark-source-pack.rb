#!/usr/bin/env ruby
# frozen_string_literal: true

require "digest"
require "fileutils"
require "json"
require "optparse"
require "pathname"
require "rubygems/package"
require "time"
require "zlib"

module P2BenchmarkSourcePack
  PACK_RELATIVE_PATH = "accepted-source-pack-v1"
  MANIFEST_RELATIVE_PATH = "#{PACK_RELATIVE_PATH}/SOURCE_PACK.json"
  INVENTORY_RELATIVE_PATH = "#{PACK_RELATIVE_PATH}/INVENTORY.sha256"
  SEAL_RELATIVE_PATH = "#{PACK_RELATIVE_PATH}/SEAL.json"
  ARTIFACT_ID = "P2_BENCHMARK_SOURCE_PACK_V1"
  ARTIFACT_ROOT_ENV = "SOURCELENS_P2_BENCHMARK_SOURCE_ROOT"
  AUTHORIZATION = "AUTHORIZE_P2_BENCHMARK_SOURCE_ADMISSION_MILESTONE_STANDARD_CURL_CAPABILITY_V1"
  INSTALLED_AT_UTC = "2026-08-16T23:52:40.385243Z"
  FREEZE_IDENTITY = {
    "relative_path" => "route3-prefreeze-gate-v1/P2_BENCHMARK_SOURCE_ROUTE3_FINAL_FREEZE_V1.json",
    "byte_length" => 85_143,
    "sha256" => "1b09848a3658f88559102eb5fbfac65ea0791b0ffa5ab839fbe6c0191314452f"
  }.freeze
  PREFREEZE_GATE_IDENTITY = {
    "relative_path" => "route3-prefreeze-gate-v1/P2_BENCHMARK_SOURCE_ROUTE3_PREFREEZE_GATE_V1.json",
    "byte_length" => 85_239,
    "sha256" => "3700b5a87ea1e0ebc8b8c772f287e54661ce48aa96dd0d1edd10a1b6c06f93d2"
  }.freeze
  FINAL_RESULT_IDENTITY = {
    "relative_path" => "route3-formal-admission-v1/FINAL_RESULT.json",
    "byte_length" => 71_165,
    "sha256" => "7282ac5d9a1973e7077b7fa3b66cd84b8076119ffeda5fe840f34c38f8ba4558"
  }.freeze
  MAVEN_MANIFEST_IDENTITY = {
    "relative_path" => "dependency-custody/route3-frozen-maven-repo-v1-manifest.json",
    "byte_length" => 1_726_432,
    "sha256" => "08636c8b5372af47d0739d26ccbbb02306ab328e43dfc85464b524ecbd6b0cb3"
  }.freeze
  PLAN_IDENTITY = {
    "relative_path" => "docs/aios/P2_RECOVERY_AND_ANTI_CYCLE_PLAN.yaml",
    "byte_length" => 7_433,
    "sha256" => "cfb383e6b89c84bfe7e574f25a6b2137f5618a7aef0a013814a7abad6d5d24ab"
  }.freeze
  CANONICAL_PARENT = {
    "branch" => "main",
    "commit" => "0a74f4b58b60aa1e16f5230d0ce34b5901f5632e",
    "tree" => "e5c5a9822bf2122aa8851a6c9d0bb53937249216"
  }.freeze
  INSTALLED_MANIFEST_IDENTITY = {
    "relative_path" => MANIFEST_RELATIVE_PATH,
    "byte_length" => 94_630,
    "sha256" => "c5f38070b8f0ed445c759f3380769c2dec5493e0f4120f681b9b1cab3fd67884"
  }.freeze
  INSTALLED_INVENTORY_IDENTITY = {
    "relative_path" => INVENTORY_RELATIVE_PATH,
    "byte_length" => 24_231,
    "sha256" => "25a42319dd373eede820fc85aeb46e384f2347f594b740e1593877c2272a4770"
  }.freeze
  INSTALLED_SEAL_IDENTITY = {
    "relative_path" => SEAL_RELATIVE_PATH,
    "byte_length" => 523,
    "sha256" => "441b816485d7ae1cd5bd9a67a0e21cddd872bf1223491fdfbf982d4e7e03bfad"
  }.freeze

  class ValidationError < StandardError; end

  class StrictHash < Hash
    def []=(key, value)
      raise ValidationError, "duplicate JSON key: #{key}" if key?(key)

      super
    end
  end

  module_function

  def assert!(condition, message)
    raise ValidationError, message unless condition
  end

  def parse_json!(bytes, label)
    JSON.parse(bytes, object_class: StrictHash)
  rescue JSON::ParserError => error
    raise ValidationError, "#{label} is invalid JSON: #{error.message}"
  end

  def canonical_json(value)
    JSON.generate(value)
  end

  def safe_relative_path!(relative, label)
    assert!(relative.is_a?(String) && !relative.empty?, "#{label} path missing")
    path = Pathname.new(relative)
    assert!(path.relative? && path.cleanpath.to_s == relative && !path.each_filename.include?(".."), "#{label} path is unsafe")
    relative
  end

  def root_path!(root)
    path = Pathname.new(root)
    stat = File.lstat(path)
    assert!(stat.directory? && !stat.symlink?, "artifact root must be a real directory")
    path.realpath
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "artifact root unavailable: #{error.message}"
  end

  def resolve!(root, relative, label)
    safe_relative_path!(relative, label)
    path = root.join(relative)
    stat = File.lstat(path)
    assert!(stat.file? && !stat.symlink? && stat.nlink == 1, "#{label} must be regular nlink1 and non-symlink")
    real = path.realpath
    assert!(real.to_s.start_with?(root.to_s + File::SEPARATOR), "#{label} escapes artifact root")
    [real, stat]
  rescue Errno::ENOENT, Errno::ELOOP => error
    raise ValidationError, "#{label} unavailable: #{error.message}"
  end

  def identity!(root, expected, label, verify_hash: true)
    assert!(expected.is_a?(Hash) && expected.keys.sort == %w[byte_length relative_path sha256], "#{label} identity is not closed")
    path, stat = resolve!(root, expected.fetch("relative_path"), label)
    assert!(stat.size == expected.fetch("byte_length"), "#{label} byte length drift")
    if verify_hash
      assert!(Digest::SHA256.file(path).hexdigest == expected.fetch("sha256"), "#{label} SHA-256 drift")
    end
    path
  end

  def actual_identity(root, relative)
    path, stat = resolve!(root, relative, relative)
    {"relative_path" => relative, "byte_length" => stat.size, "sha256" => Digest::SHA256.file(path).hexdigest}
  end

  def archive_license!(archive_path, top_directory, expected_file_count)
    safe_relative_path!(top_directory, "archive top directory")
    regular_count = 0
    license = nil
    Zlib::GzipReader.open(archive_path) do |gzip|
      Gem::Package::TarReader.new(gzip) do |tar|
        tar.each do |entry|
          name = entry.full_name
          next if name == "pax_global_header" && entry.header.typeflag == "g"

          path = Pathname.new(name)
          assert!(path.relative? && !path.each_filename.include?(".."), "archive member path is unsafe")
          assert!(name == top_directory || name.start_with?(top_directory + "/"), "archive has more than one top directory")
          assert!(!%w[1 2].include?(entry.header.typeflag), "archive contains a link")
          next unless entry.file?

          regular_count += 1
          next unless ["#{top_directory}/LICENSE", "#{top_directory}/LICENSE.txt"].include?(name)

          bytes = entry.read
          assert!(bytes.include?("Apache License") && bytes.include?("Version 2.0, January 2004"), "archive license is not Apache-2.0 text")
          license = {
            "archive_relative_path" => name.delete_prefix(top_directory + "/"),
            "byte_length" => bytes.bytesize,
            "sha256" => Digest::SHA256.hexdigest(bytes),
            "classification" => "APACHE_LICENSE_2_0_TEXT_PRESENT"
          }
        end
      end
    end
    assert!(regular_count == expected_file_count, "archive regular-file count drift")
    assert!(license, "archive license is missing")
    license
  rescue Zlib::GzipFile::Error, Gem::Package::TarInvalidError => error
    raise ValidationError, "archive is invalid: #{error.message}"
  end

  def validate_maven_custody!(root, verify_files:)
    path = identity!(root, MAVEN_MANIFEST_IDENTITY, "frozen Maven manifest")
    manifest = parse_json!(File.binread(path), "frozen Maven manifest")
    assert!(manifest["schema_version"] == "p2-route3-frozen-maven-custody/v1" && manifest["status"] == "PASS", "frozen Maven custody is not PASS")
    assert!(manifest["authorization_scope"] == "CAPABILITY_SHARED_PUBLIC_MAVEN_BYTES_PLUS_ROUTE3_EXACT_CURL", "frozen Maven authorization drift")
    assert!(manifest["copy_mode"] == "APFS_CLONE_CREATE_ONCE_NLINK1" && manifest["network_used"] == false, "frozen Maven copy/network mode drift")
    assert!(manifest["candidate_source_or_selector_lineage_copied"] == false, "rejected candidate lineage entered Maven custody")
    inventory = manifest.fetch("inventory")
    assert!(inventory.is_a?(Array) && inventory.length == 2_501, "frozen Maven inventory count drift")
    assert!(manifest["receipt_bound_file_count"] == 2_501 && manifest["shared_base_file_count"] == 2_037 && manifest["route3_exact_install_file_count"] == 464 && manifest["unexpected_unbound_file_count"] == 0, "frozen Maven custody accounting drift")
    assert!(Digest::SHA256.hexdigest(JSON.generate(inventory)) == manifest["inventory_json_sha256"], "frozen Maven inventory JSON hash drift")
    if verify_files
      inventory.each_with_index do |entry, index|
        expected = {
          "relative_path" => entry.fetch("frozen_relative_path"),
          "byte_length" => entry.fetch("byte_length"),
          "sha256" => entry.fetch("sha256")
        }
        identity!(root, expected, "frozen Maven entry #{index + 1}")
      end
    end
    manifest
  end

  def checked_receipt!(root, identity, expected_pack, expected_task, label)
    path = identity!(root, identity, label)
    receipt = parse_json!(File.binread(path), label)
    assert!(receipt["schema_version"] == "p2-prefreeze-fix-side-test-overlay/v1" && receipt["status"] == "PASS", "#{label} is not PASS")
    assert!(receipt["overlay_pack_basename"] == expected_pack && receipt["task_id"].include?(expected_task), "#{label} task/pack drift")
    assert!(receipt["fresh_base_extraction"] == true && receipt["product_fix_bytes_applied"] == false && receipt["formal_selector_count"] == 0, "#{label} execution boundary drift")
    assert!(receipt["overlay_leaf_count"] == receipt.fetch("overlay_leaves").length && receipt["overlay_leaf_count"].positive?, "#{label} overlay inventory drift")
    receipt
  end

  def build_manifest!(root, verify_maven_files: true)
    freeze_path = identity!(root, FREEZE_IDENTITY, "final freeze")
    prefreeze_path = identity!(root, PREFREEZE_GATE_IDENTITY, "prefreeze gate")
    final_path = identity!(root, FINAL_RESULT_IDENTITY, "formal admission result")
    freeze = parse_json!(File.binread(freeze_path), "final freeze")
    prefreeze = parse_json!(File.binread(prefreeze_path), "prefreeze gate")
    final = parse_json!(File.binread(final_path), "formal admission result")
    validate_maven_custody!(root, verify_files: verify_maven_files)

    assert!(freeze["schema_version"] == "p2-benchmark-source-route3-final-freeze/v1" && freeze["status"] == "FROZEN_PENDING_ONE_SHOT_FORMAL_ADMISSION", "final freeze schema/status drift")
    assert!(freeze["authorization"] == AUTHORIZATION && freeze["canonical"].slice("branch", "commit", "tree") == CANONICAL_PARENT, "final freeze authorization/canonical drift")
    assert!(freeze["recovery_plan"] == PLAN_IDENTITY, "final freeze recovery-plan drift")
    assert!(freeze["prefreeze_gate"] == PREFREEZE_GATE_IDENTITY, "final freeze prefreeze identity drift")
    assert!(freeze["frozen_maven_custody"] == MAVEN_MANIFEST_IDENTITY, "final freeze Maven identity drift")
    assert!(prefreeze["schema_version"] == "p2-benchmark-source-route3-prefreeze-gate/v1" && prefreeze["status"] == "PASS", "prefreeze Gate is not PASS")
    assert!(prefreeze["all_24_test_compile_pass"] == true && prefreeze["all_24_unrelated_provider_smoke_pass"] == true && prefreeze["formal_dispatch_count"] == 0 && prefreeze["formal_selector_count"] == 0, "prefreeze Gate execution boundary drift")
    assert!(final["schema_version"] == "p2-benchmark-source-route3-formal-final/v1" && final["status"] == "ACCEPTED" && final["source_admission_accepted"] == true, "formal source admission is not ACCEPTED")
    assert!(final["accepted_task_count"] == 12 && final["formal_process_count"] == 24 && final["formal_selector_count"] == 24 && final["rerun_count"] == 0 && final["result_integrity_non_pass_count"] == 0, "formal source-admission accounting drift")
    assert!(final["p2_strict_progress_credit"] == 0 && final["p2_delivery_credit"] == 0 && final["p3_status"] == "HOLD", "formal result created false progress")
    assert!(final["capability_lifecycle"] == "ENDS_ON_SOURCE_ADMISSION_ACCEPTED", "network capability lifecycle drift")
    assert!(final["freeze"] == FREEZE_IDENTITY, "formal result freeze binding drift")
    assert!(freeze["repository_count"] == 6 && freeze["task_count"] == 12 && freeze["tasks_per_repository"] == 2, "frozen source-pack cardinality drift")
    assert!(freeze["formal_dispatch_count"] == 0 && freeze["formal_selector_count"] == 0 && freeze["mutation_after_freeze_allowed"] == false && freeze["rerun_to_pass_allowed"] == false, "freeze lifecycle drift")

    formal_by_task = final.fetch("tasks").to_h { |task| [task.fetch("task_id"), task] }
    inventory = [FREEZE_IDENTITY, PREFREEZE_GATE_IDENTITY, FINAL_RESULT_IDENTITY, MAVEN_MANIFEST_IDENTITY]
    tasks = freeze.fetch("tasks").map do |task|
      task_id = task.fetch("task_id")
      formal = formal_by_task.fetch(task_id)
      assert!(formal["accepted"] == true && formal["split"] == task["split"], "#{task_id} formal verdict drift")
      %w[base fix].each do |side|
        result = formal.fetch(side)
        expected_status = side == "base" ? "EXPECTED_FAIL" : "PASS"
        assert!(result["status"] == expected_status && result["selector"] == task["selector"] && result["rerun_count"] == 0, "#{task_id} #{side} formal result drift")
        inventory << result.fetch("result_identity") << result.fetch("pre_spawn_identity")
      end

      sides = {}
      {"base" => task.fetch("overlay_receipt"), "fix" => task.fetch("fix_pack_receipt")}.each do |side, receipt_identity|
        pack = task.fetch(side).fetch("pack_basename")
        receipt = checked_receipt!(root, receipt_identity, pack, task_id, "#{task_id} #{side} pack receipt")
        archive = receipt.fetch("base_archive")
        archive_identity = {
          "relative_path" => archive.fetch("response_relative_path"),
          "byte_length" => archive.fetch("response_byte_length"),
          "sha256" => archive.fetch("response_sha256")
        }
        archive_path = identity!(root, archive_identity, "#{task_id} #{side} archive")
        license = archive_license!(archive_path, archive.fetch("top_directory"), archive.fetch("regular_file_count"))
        inventory << receipt_identity << archive_identity
        sides[side] = {
          "commit" => task.fetch(side).fetch("commit"),
          "tree" => task.fetch(side).fetch("tree"),
          "pack_basename" => pack,
          "archive" => archive_identity.merge(
            "requested_url" => archive.fetch("requested_url"),
            "top_directory" => archive.fetch("top_directory"),
            "regular_file_count" => archive.fetch("regular_file_count")
          ),
          "license" => license,
          "test_overlay_receipt" => receipt_identity,
          "test_overlay_leaves" => receipt.fetch("overlay_leaves")
        }
      end
      inventory << task.fetch("pr_list_response") << task.fetch("pr_files_response")
      %w[base fix].each do |side|
        task.fetch(side).fetch("commit_api").each_value { |identity| inventory << identity }
      end
      {
        "task_id" => task_id,
        "repository" => task.fetch("repository"),
        "pull_request" => task.fetch("pr"),
        "split" => task.fetch("split"),
        "selector" => task.fetch("selector"),
        "candidate_selector_source" => task.fetch("candidate_selector_source"),
        "base" => sides.fetch("base"),
        "fix" => sides.fetch("fix"),
        "provenance" => {
          "pull_request_list_response" => task.fetch("pr_list_response"),
          "pull_request_files_response" => task.fetch("pr_files_response"),
          "base_commit_api" => task.fetch("base").fetch("commit_api"),
          "fix_commit_api" => task.fetch("fix").fetch("commit_api")
        }
      }
    end
    assert!(tasks.group_by { |task| task["repository"] }.values.all? { |group| group.length == 2 }, "source-pack tasks are not exactly two per repository")
    assert!(tasks.count { |task| task["split"] == "DEV" } == 8 && tasks.count { |task| task["split"] == "HELD" } == 4, "source-pack split drift")

    unique_inventory = inventory.uniq { |entry| entry.fetch("relative_path") }.sort_by { |entry| entry.fetch("relative_path") }
    unique_inventory.each_with_index { |identity, index| identity!(root, identity, "source-pack inventory #{index + 1}") }
    manifest = {
      "schema_version" => "p2-benchmark-source-pack/v1",
      "artifact_id" => ARTIFACT_ID,
      "status" => "ACCEPTED_INSTALLED_CREATE_ONCE",
      "artifact_root_contract" => {
        "configuration_environment_variable" => ARTIFACT_ROOT_ENV,
        "all_artifact_paths_are_root_relative" => true,
        "absolute_path_embedded" => false
      },
      "authorization" => AUTHORIZATION,
      "authorization_lifecycle" => "ENDED_ON_SOURCE_ADMISSION_ACCEPTED",
      "canonical_parent" => CANONICAL_PARENT,
      "recovery_plan" => PLAN_IDENTITY,
      "source_admission" => {
        "status" => "ACCEPTED",
        "final_result" => FINAL_RESULT_IDENTITY,
        "freeze" => FREEZE_IDENTITY,
        "prefreeze_gate" => PREFREEZE_GATE_IDENTITY,
        "formal_process_count" => 24,
        "rerun_count" => 0
      },
      "dependency_custody" => {
        "manifest" => MAVEN_MANIFEST_IDENTITY,
        "repository_relative_path" => "dependency-custody/route3-frozen-maven-repo-v1",
        "file_count" => 2_501,
        "inventory_json_sha256" => "ea4a01e3f5ba2ed70a4ccd1133b5866064e3f2c5a3885610e0cd59e6dcff0b68"
      },
      "counts" => {"repositories" => 6, "tasks" => 12, "source_archives" => 24, "dev_tasks" => 8, "held_tasks" => 4},
      "split" => freeze.fetch("split"),
      "tasks" => tasks,
      "inventory" => unique_inventory,
      "progress" => {"p2_strict_percent" => 0, "p2_delivery_percent" => 0, "source_admission_progress_credit" => 0, "p3_status" => "HOLD"},
      "installed_at_utc" => INSTALLED_AT_UTC
    }
    [manifest, unique_inventory]
  end

  def exclusive_write(path, bytes, mode: 0o444)
    flags = File::WRONLY | File::CREAT | File::EXCL
    flags |= File::NOFOLLOW if File.const_defined?(:NOFOLLOW)
    File.open(path, flags, mode) do |file|
      file.binmode
      file.write(bytes)
      file.flush
      file.fsync
    end
  end

  def install!(root, stage_parent)
    root = root_path!(root)
    final = root.join(PACK_RELATIVE_PATH)
    assert!(!final.exist? && !final.symlink?, "create-once source-pack target already exists")
    stage_parent = root_path!(stage_parent)
    assert!(File.stat(root).dev == File.stat(stage_parent).dev, "stage and artifact root must be on one filesystem")
    stage = stage_parent.join("p2-source-pack-stage-#{Process.pid}-#{Time.now.to_i}")
    Dir.mkdir(stage, 0o700)
    begin
      manifest, inventory = build_manifest!(root)
      manifest_bytes = canonical_json(manifest) + "\n"
      inventory_bytes = inventory.map { |entry| "#{entry.fetch('sha256')}  #{entry.fetch('byte_length')}  #{entry.fetch('relative_path')}" }.join("\n") + "\n"
      exclusive_write(stage.join("SOURCE_PACK.json"), manifest_bytes)
      exclusive_write(stage.join("INVENTORY.sha256"), inventory_bytes)
      seal = {
        "schema_version" => "p2-benchmark-source-pack-seal/v1",
        "artifact_id" => ARTIFACT_ID,
        "status" => "SEALED_CREATE_ONCE",
        "source_pack" => {"relative_path" => MANIFEST_RELATIVE_PATH, "byte_length" => manifest_bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(manifest_bytes)},
        "inventory" => {"relative_path" => INVENTORY_RELATIVE_PATH, "byte_length" => inventory_bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(inventory_bytes)},
        "referenced_artifact_count" => inventory.length,
        "p2_progress_credit" => 0
      }
      exclusive_write(stage.join("SEAL.json"), canonical_json(seal) + "\n")
      File.rename(stage, final)
    ensure
      Dir.rmdir(stage) if stage.exist? && stage.directory? && Dir.empty?(stage)
    end
    verify!(root, verify_maven_files: true)
  end

  def verify!(root, verify_maven_files: true)
    root = root_path!(root)
    manifest_path = identity!(root, INSTALLED_MANIFEST_IDENTITY, "installed source-pack manifest")
    inventory_path = identity!(root, INSTALLED_INVENTORY_IDENTITY, "installed source-pack inventory")
    seal_path = identity!(root, INSTALLED_SEAL_IDENTITY, "installed source-pack seal")
    manifest_bytes = File.binread(manifest_path)
    inventory_bytes = File.binread(inventory_path)
    seal = parse_json!(File.binread(seal_path), "installed source-pack seal")
    manifest = parse_json!(manifest_bytes, "installed source-pack manifest")
    assert!(seal["schema_version"] == "p2-benchmark-source-pack-seal/v1" && seal["artifact_id"] == ARTIFACT_ID && seal["status"] == "SEALED_CREATE_ONCE", "source-pack seal drift")
    assert!(seal["source_pack"] == {"relative_path" => MANIFEST_RELATIVE_PATH, "byte_length" => manifest_bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(manifest_bytes)}, "source-pack seal manifest binding drift")
    assert!(seal["inventory"] == {"relative_path" => INVENTORY_RELATIVE_PATH, "byte_length" => inventory_bytes.bytesize, "sha256" => Digest::SHA256.hexdigest(inventory_bytes)}, "source-pack seal inventory binding drift")
    assert!(manifest["schema_version"] == "p2-benchmark-source-pack/v1" && manifest["artifact_id"] == ARTIFACT_ID && manifest["status"] == "ACCEPTED_INSTALLED_CREATE_ONCE", "installed source-pack schema/status drift")
    assert!(manifest["artifact_root_contract"] == {"configuration_environment_variable" => ARTIFACT_ROOT_ENV, "all_artifact_paths_are_root_relative" => true, "absolute_path_embedded" => false}, "installed source-pack root contract drift")
    assert!(manifest["authorization"] == AUTHORIZATION && manifest["authorization_lifecycle"] == "ENDED_ON_SOURCE_ADMISSION_ACCEPTED", "installed source-pack authorization lifecycle drift")
    assert!(manifest["canonical_parent"] == CANONICAL_PARENT && manifest["recovery_plan"] == PLAN_IDENTITY, "installed source-pack canonical/plan binding drift")
    assert!(manifest["counts"] == {"repositories" => 6, "tasks" => 12, "source_archives" => 24, "dev_tasks" => 8, "held_tasks" => 4}, "installed source-pack count drift")
    assert!(manifest["progress"] == {"p2_strict_percent" => 0, "p2_delivery_percent" => 0, "source_admission_progress_credit" => 0, "p3_status" => "HOLD"}, "installed source-pack false progress")
    inventory = manifest.fetch("inventory")
    assert!(seal["referenced_artifact_count"] == inventory.length && seal["p2_progress_credit"] == 0, "source-pack seal accounting drift")
    expected_inventory = inventory.map { |entry| "#{entry.fetch('sha256')}  #{entry.fetch('byte_length')}  #{entry.fetch('relative_path')}" }.join("\n") + "\n"
    assert!(inventory_bytes == expected_inventory, "installed source-pack inventory content drift")
    inventory.each_with_index { |identity, index| identity!(root, identity, "installed source-pack artifact #{index + 1}") }
    validate_maven_custody!(root, verify_files: verify_maven_files)
    {"manifest" => actual_identity(root, MANIFEST_RELATIVE_PATH), "inventory" => actual_identity(root, INVENTORY_RELATIVE_PATH), "seal" => actual_identity(root, SEAL_RELATIVE_PATH), "task_count" => manifest.fetch("tasks").length, "maven_file_rehash" => verify_maven_files}
  end
end

if $PROGRAM_NAME == __FILE__
  options = {install: false, verify_maven_files: true, stage_parent: "/private/tmp"}
  parser = OptionParser.new do |opt|
    opt.on("--artifact-root PATH") { |value| options[:artifact_root] = value }
    opt.on("--install") { options[:install] = true }
    opt.on("--stage-parent PATH") { |value| options[:stage_parent] = value }
    opt.on("--skip-maven-file-rehash") { options[:verify_maven_files] = false }
  end
  parser.parse!
  begin
    raise P2BenchmarkSourcePack::ValidationError, "--artifact-root is required" unless options[:artifact_root]
    result = if options[:install]
               P2BenchmarkSourcePack.install!(options[:artifact_root], options[:stage_parent])
             else
               P2BenchmarkSourcePack.verify!(options[:artifact_root], verify_maven_files: options[:verify_maven_files])
             end
    puts "P2_BENCHMARK_SOURCE_PACK: PASS #{JSON.generate(result)}"
  rescue P2BenchmarkSourcePack::ValidationError, KeyError, JSON::ParserError,
         Errno::ENOENT, Errno::EEXIST, Errno::ELOOP, SystemCallError => error
    warn "P2_BENCHMARK_SOURCE_PACK: NON_PASS #{error.message}"
    exit 1
  end
end

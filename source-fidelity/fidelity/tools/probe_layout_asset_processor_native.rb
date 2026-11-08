# frozen_string_literal: true
# Standalone native feasibility component. NEVER accepts request/HTML/page/019.
require "json"
require "digest"
require "open3"
require "fileutils"
require "tmpdir"
require "rubygems/package"
require "zlib"
require "stringio"
require_relative "source_package"
require_relative "../compat/discourse/lib/site_settings/portable_global_configuration"
root = File.expand_path("../..", __dir__)
build = Dir.mktmpdir("native-asset-vm-", File.join(root, "fidelity/build"))
proof = {status: "in_progress", scope: "Ruby-free original MiniRacer V8 feasibility ONLY", native_request_accepted: false, html_accepted: false, page_accepted: false, commands: [], packages: []}
save = -> { File.write(File.join(build, "evidence.json"), JSON.pretty_generate(proof) + "\n") }
command = lambda do |name, argv, environment = {}|
  output, error, status = Open3.capture3(environment, *argv, chdir: root)
  File.write(File.join(build, "#{name}.stdout"), output)
  File.write(File.join(build, "#{name}.stderr"), error)
  proof[:commands] << {name: name, argv: argv, returncode: status.exitstatus}
  save.call
  [output, error, status.exitstatus]
end
begin
  configuration = SiteSettings::PortableGlobalConfiguration.new([], File.join(root, "discourse/config/discourse_defaults.conf"), File.join(root, "discourse/config/discourse.conf"))
  mode = configuration.value("mini_racer_single_threaded")
  raise "invalid original VM configuration type" unless mode == true || mode == false
  proof[:configured_single_threaded] = mode
  %w[mini_racer_v8.cc mini_racer_v8.h].each do |member|
    bytes, metadata = FidelitySourcePackage.member(root, "mini_racer-0.22.1", "ext/mini_racer_extension/#{member}")
    proof[:packages] << metadata
    File.binwrite(File.join(build, member), bytes)
  end
  package = "libv8-node-24.12.0.1-x86_64-linux"
  archive = File.join(root, "run/bundle/ruby/4.0.0/cache/#{package}.gem")
  checksum = Digest::SHA256.file(archive).hexdigest
  lock = File.read(File.join(root, "discourse/Gemfile.lock"))
  raise "unlocked native V8 archive" unless lock.include?("libv8-node (24.12.0.1-x86_64-linux) sha256=#{checksum}")
  Gem::Package.new(archive).verify
  gem_root = File.join(root, "run/bundle/ruby/4.0.0/gems/#{package}")
  lib_member = "vendor/v8/x86_64-linux/libv8/obj/libv8_monolith.a"
  library = File.join(gem_root, lib_member)
  expected = nil
  headers = {}
  File.open(archive, "rb") do |file|
    Gem::Package::TarReader.new(file) do |outer|
      outer.each do |entry|
        next unless entry.full_name == "data.tar.gz"
        Gem::Package::TarReader.new(Zlib::GzipReader.new(StringIO.new(entry.read))) do |data|
          data.each do |item|
            expected = Digest::SHA256.hexdigest(item.read) if item.full_name == lib_member
            if item.file? && item.full_name.start_with?("vendor/v8/include/")
              bytes = item.read
              raise "installed V8 header differs #{item.full_name}" unless File.binread(File.join(gem_root, item.full_name)) == bytes
              headers[item.full_name] = Digest::SHA256.hexdigest(bytes)
            end
          end
        end
      end
    end
  end
  raise "installed V8 library differs from package" unless expected && Digest::SHA256.file(library).hexdigest == expected
  proof[:packages] << {gem: package, sha256: checksum, library_sha256: expected, headers: headers}
  original, error, code = command.call("original-inspection", ["bundle", "exec", "ruby", File.join(root, "fidelity/tools/inspect_layout_asset_processor.rb")], {"BUNDLE_GEMFILE" => File.join(root, "discourse/Gemfile")})
  raise "original VM inspection failed: #{error}" unless code == 0
  reference = JSON.parse(original)
  raise "original fixture cleanup failed" unless reference.fetch("owned_fixture_removed") && reference.fetch("ruby_threads_before") == reference.fetch("ruby_threads_after_dispose")
  proof[:original_inspection] = reference
  native = File.join(build, "probe")
  source = File.join(root, "fidelity/test/layout_asset_processor_native.cc")
  proof[:adapter_sha256] = Digest::SHA256.file(source).hexdigest
  _, error, code = command.call("compile", ["clang++", "-std=c++20", "-O1", "-fno-rtti", "-fno-strict-aliasing", "-pthread", "-I#{File.join(gem_root, 'vendor/v8/include')}", "-I#{build}", "-DMINI_RACER_SOURCE=\"#{File.join(build, 'mini_racer_v8.cc')}\"", source, library, "-ldl", "-lrt", "-o", native])
  raise "native VM build failed: #{error[-2000..]}" unless code == 0
  library_target = File.join(build, "libowned_layout_vm.so")
  _, error, code = command.call("compile-library", ["clang++", "-std=c++20", "-O1", "-fno-rtti", "-fno-strict-aliasing", "-pthread", "-fPIC", "-shared", "-DFIDELITY_V8_LIBRARY", "-I#{File.join(gem_root, 'vendor/v8/include')}", "-I#{build}", "-DMINI_RACER_SOURCE=\"#{File.join(build, 'mini_racer_v8.cc')}\"", source, library, "-ldl", "-lrt", "-o", library_target])
  raise "native VM library build failed" unless code == 0
  proof[:native_library] = {path: library_target, sha256: Digest::SHA256.file(library_target).hexdigest}
  fixtures = []
  begin
    cases = {"native" => nil, "unit-exception" => 'globalThis.emberVersion = function(){ throw new Error("unit-only-vm-exception"); };',
      "unit-logger" => 'globalThis.emberVersion = function(){ rails.logger.info("unit-only-vm-log"); return "unit-only-vm-result"; };',
      "unit-timeout" => 'globalThis.emberVersion = function(){ while(true){} };'}
    cases.each do |name, unit_source|
      fixture = Dir.mktmpdir("#{name}-", build)
      fixtures << fixture
      path = File.join(fixture, "asset-processor.js")
      if unit_source
        File.write(path, unit_source)
      else
        # Only cached source bytes, NOT original output/observed version.
        cached = Dir.glob(File.join(root, "discourse/tmp/asset-processor/asset-processor-*.js")).find { |item| Digest::SHA256.file(item).hexdigest == reference.fetch("bundle_sha256") }
        raise "original cached bundle absent" unless cached
        FileUtils.copy_file(cached, path)
      end
      trace = File.join(build, "#{name}.trace")
      output, error, code = command.call(name, ["strace", "-f", "-e", "trace=execve,connect", "-o", trace, native, path], {"FIDELITY_OWNED_VM_FIXTURE" => fixture, "FIDELITY_VM_SINGLE_THREADED" => (mode ? "1" : "0")})
      tracing = File.read(trace)
      raise "native VM external process/endpoint" unless tracing.scan("execve(").size == 1 && !tracing.include?("connect(")
      raise "native VM cleanup not observed" unless output.include?("disposed=1 joined=1") && output.include?("threads_before=1 threads_after=1")
      if name == "native"
        version = output[/^FIDELITY_NATIVE_VM_VERSION (.+)$/, 1]
        raise "native/original version mismatch" unless code == 0 && version == reference.fetch("ember_version")
        proof[:native_version] = version
      elsif name == "unit-logger"
        raise "real logger callback failed" unless code == 0 && output.include?("callbacks=2") && error.include?("unit-only-vm-log") && output.include?("unit-only-vm-result")
      else
        raise "native error/timeout not refused" unless code == 5
      end
    end
  ensure
    fixtures.each { |fixture| FileUtils.remove_entry_secure(fixture) if File.directory?(fixture) }
    proof[:owned_fixture_cleanup] = fixtures.all? { |fixture| !File.exist?(fixture) }
  end
  proof[:status] = "PASS_SCOPED_RUBY_FREE_ORIGINAL_V8_VERSION_COMPONENT"
rescue Exception => error
  proof[:status] = "FAILED_NATIVE_V8_COMPONENT"
  proof[:error] = error.message
  raise
ensure
  save.call
  puts build
end

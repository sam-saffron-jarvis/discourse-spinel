# frozen_string_literal: true
# READONLY isolated original-method inspection. NOT native/layout acquisition.
require "prism"
require "pathname"
require "digest"
require "json"
require "fileutils"
require "tmpdir"
require "logger"
require "open3"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {purpose: "isolated original V8/version effect inspection; NEVER production input", source: {}, packages: [], native_accepted: false, html_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "asset inspection source mismatch #{path}" unless status.success? && source.b == File.binread(File.join(root, "discourse", path))
  proof[:source][path] = Digest::SHA256.hexdigest(source)
  source
end
precompiled = read.call("lib/precompiled_bundle.rb")
processor = read.call("lib/asset_processor.rb")
_, member = FidelitySourcePackage.member(root, "mini_racer-0.22.1", "lib/mini_racer.rb")
proof[:packages] << member
# No full Rails boot/application/global Source SDK in this independent process.
require "mini_racer"
require_relative "../compat/discourse/lib/site_settings/portable_global_configuration"
configuration = SiteSettings::PortableGlobalConfiguration.new([], File.join(root, "discourse/config/discourse_defaults.conf"), File.join(root, "discourse/config/discourse.conf"))
module Rails
  class << self; attr_accessor :root; end
  def self.logger; @logger ||= Logger.new($stderr); end
end
module GlobalSetting
  class << self; attr_accessor :configuration; end
  def self.mini_racer_single_threaded; configuration.value("mini_racer_single_threaded"); end
end
GlobalSetting.configuration = configuration
# Source-specific platform admission, not a Rails initializer campaign. Apply
# the exact original flag API only when the REAL configuration enables it.
read.call("config/initializers/000-mini_racer.rb")
MiniRacer::Platform.set_flags!(:single_threaded) if GlobalSetting.mini_racer_single_threaded
proof[:configured_single_threaded] = GlobalSetting.mini_racer_single_threaded
owner = Prism.parse(processor).value.statements.body.grep(Prism::ClassNode).first
bundle_node = owner.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :BUNDLE }
raise "unknown bundle declaration" unless bundle_node.value.receiver&.slice == "PrecompiledBundle"
# Capture constructor declarations WITHOUT ever executing its external build.
declarations = {}
constructor = Object.new
constructor.define_singleton_method(:new) { |**args, &block| declarations.replace(args); nil }
namespace = Module.new
namespace.const_set(:PrecompiledBundle, constructor)
namespace.module_eval(bundle_node.slice)
fixture = Dir.mktmpdir("asset-processor-inspection-", File.join(root, "fidelity/build"))
context_owner = nil
begin
  source_root = File.join(root, "discourse")
  declarations.fetch(:dependency_globs).each do |glob|
    files = Dir.glob(glob, base: source_root).sort
    raise "empty original bundle glob" if files.empty?
    files.each do |path|
      target = File.join(fixture, path)
      FileUtils.mkdir_p(File.dirname(target))
      FileUtils.copy_file(File.join(source_root, path), target)
    end
  end
  Rails.root = Pathname.new(source_root)
  Object.class_eval(precompiled, "original PrecompiledBundle")
  original_bundle = PrecompiledBundle.new(**declarations) { raise "external asset build refused" }
  original_path = original_bundle.path
  raise "original bundle would require external build" unless original_bundle.precompiled?
  proof[:bundle_sha256] = Digest::SHA256.file(original_path).hexdigest
  Rails.root = Pathname.new(fixture)
  bundle = PrecompiledBundle.new(**declarations) { raise "external asset build refused" }
  target = bundle.path
  FileUtils.mkdir_p(File.dirname(target))
  FileUtils.copy_file(original_path, target)
  raise "copied bundle mismatch" unless Digest::SHA256.file(target).hexdigest == proof[:bundle_sha256]
  raise "owned bundle not precompiled" unless bundle.precompiled?
  selected = %i[create_new_context timeout mutex v8 v8_call ember_version reset_context]
  methods = owner.body.body.grep(Prism::DefNode).select { |node| selected.include?(node.name) }
  raise "inspection source method missing" unless methods.map(&:name).sort == selected.sort
  context_owner = Module.new
  context_owner.const_set(:BUNDLE, bundle)
  context_owner.module_eval("@mutex = Mutex.new; @ctx_init = Mutex.new\n" + methods.map(&:slice).join("\n"), "original scoped AssetProcessor")
  context_owner.define_singleton_method(:load_or_build_processor_source) { bundle.load_or_build }
  before = Thread.list.size
  proof[:ember_version] = context_owner.ember_version
  context_owner.reset_context
  proof[:ruby_threads_before] = before
  proof[:ruby_threads_after_dispose] = Thread.list.size
  proof[:source_method_sha256] = methods.to_h { |node| [node.name, Digest::SHA256.hexdigest(node.slice)] }
  proof[:external_build_dispatched] = false
  proof[:pg_dispatched] = false
ensure
  context_owner.reset_context if context_owner
  FileUtils.remove_entry_secure(fixture) if File.directory?(fixture)
  proof[:owned_fixture_removed] = !File.exist?(fixture)
end
puts JSON.pretty_generate(proof)

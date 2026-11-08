# frozen_string_literal: true
# Request integration only; does not substitute a unit graph/settings/URL host.
require "prism"
require "digest"
require "json"
require "open3"
require "action_view"
require "action_view/template/handlers/erb/erubi"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
build = ARGV.fetch(0)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, sources: {}, spans: [], framework: [], page_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "request asset source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  proof[:sources][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |source, name|
  found = []
  visit = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |c| visit.call(c) }
  end
  visit.call(Prism.parse(source).value)
  raise "asset source method ambiguous #{name}" unless found.size == 1
  node = found.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
helper = read.call("app/helpers/application_helper.rb")
initializer = read.call("config/initializers/assets.rb")
# Acquire the initializer's actual concrete root expressions, not an observed
# load-path list. Plugins are checked empty before these expressions are used.
owner = Prism.parse(initializer).value.statements.body
push = owner.grep(Prism::CallNode).find { |n| n.name == :push && n.receiver&.slice == "Rails.application.config.assets.paths" }
raise "asset initializer roots changed" unless push && push.arguments.arguments.size == 4
roots = push.arguments.arguments.map(&:slice).map { |s| s.gsub('Rails.public_path.join(', 'File.join(root, "public", ').gsub('Rails.root.join(', 'File.join(root, ') }
version = owner.grep(Prism::CallNode).find { |n| n.name == :version= }
raise "asset version initializer changed" unless version && version.arguments.slice == '"2-#{GlobalSetting.asset_url_salt}"'
paths = "module RequestAssetSource\ndef self.paths(root)\n[#{roots.join(', ')}]\nend\ndef self.version(settings)\n#{version.arguments.slice.gsub('GlobalSetting.', 'settings.')}\nend\nend\n"
File.write(File.join(build, "request_asset_paths_source.rb"), paths)
url_names = %i[script_asset_path asset_cdn_path is_brotli_req?]
url_methods = url_names.map { |n| select.call(helper, n) }
native_urls = url_methods.map do |text|
  text.gsub("ActionController::Base.helpers", "asset_paths").gsub("ActionController::Base.config.relative_url_root", "settings.relative_url_root").gsub("GlobalSetting.", "settings.").sub('settings.s3_asset_cdn_url.presence', '(ActiveSupport.blank?(settings.s3_asset_cdn_url) ? nil : settings.s3_asset_cdn_url)')
end
native_urls[0] = native_urls[0].sub('def script_asset_path(', 'def source_script_asset_path(')
original_urls = url_methods.map { |text| text.sub('def script_asset_path(', 'def source_script_asset_path(') }
original_map = select.call(helper, :generate_import_map).sub('def generate_import_map(', 'def source_generate_import_map(')
# The no-loaded-plugin precondition is checked at runtime. Only the empty
# plugin loops fold; theme external imports remain genuinely computed and the
# original missing-plugin stub methods are retained.
native_map = original_map.dup
first = native_map.index('    imports =')
last = native_map.index('    external_plugin_imports.each')
raise "import-map no-plugin source boundary changed" unless first && last
native_map[first...last] = <<~'RUBY'
    raise ArgumentError, 'unsupported loaded request asset plugins' unless plugin_assets.empty? && Discourse.plugins.empty?
    imports = {}
    available_plugins = []
    external_plugin_imports = theme_js_assets.flat_map do |asset|
      external = asset[:external_plugin_imports]
      raise TypeError, 'Theme external imports are not Array' unless external.is_a?(Array)
      external
    end.uniq
RUBY
native_map = native_map.gsub('EmberAssets.import_map', 'request_assets.import_map').gsub('JSON.pretty_generate({ imports: }).html_safe', 'ActionView::HtmlFragment.new(JSON.pretty_generate({ imports: }))')
stubs = read.call("lib/plugin/js_manager.rb")
stubs = %i[optional_plugin_stub required_plugin_stub].map { |n| select.call(stubs, n) }.join("\n").gsub('message.to_json', 'JSON.generate(message)')
File.write(File.join(build, "request_asset_helpers.rb"), "module RequestAssetHelpers\n#{native_urls.join("\n")}\n#{native_map}\nend\nmodule Plugin\nclass JsManager\n#{stubs}\nend\nend\n")
# Compile the whole original partial in both candidates now that acquisition
# returns. No plugin loops or trailing partial bytes are truncated.
partial = read.call("app/views/layouts/_plugin_js.html.erb")
code = ActionView::Template::Handlers::ERB::Erubi.new(partial, escape: false, trim: true).src.dup
# The full partial contains calls for loaded plugin records outside this scoped
# no-plugin profile. Fold ONLY those provably empty loop bodies, retaining every
# literal outside them (including trailing whitespace). The original executes
# the complete unmodified compiled partial in the third process.
empty_loops = []
visit = lambda do |node|
  if node.is_a?(Prism::CallNode) && node.name == :each && node.receiver&.slice&.start_with?('plugin_assets')
    empty_loops << node
  else
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
end
visit.call(Prism.parse(code).value)
raise 'plugin loop scope changed' unless empty_loops.size == 2
empty_loops.sort_by { |node| -node.location.start_offset }.each do |node|
  code[node.location.start_offset, node.location.length] = "raise ArgumentError, 'unsupported importmap partial plugins' unless plugin_assets.empty?"
end
File.write(File.join(build, "native_importmap_prefix.rb"), "module NativeImportMapPrefix\ndef render_plugin_js_prefix(opts)\n#{code}\nend\nend\n")
framework = {}
%w[lib/propshaft/asset.rb lib/propshaft/load_path.rb lib/propshaft/resolver/dynamic.rb lib/propshaft/helper.rb lib/propshaft/railtie.rb lib/propshaft/assembly.rb lib/propshaft/compiler.rb lib/propshaft/compilers.rb].each do |path|
  bytes, metadata = FidelitySourcePackage.member(root, "propshaft-1.3.2", path)
  framework[path] = bytes
  proof[:framework] << metadata
end
_, metadata = FidelitySourcePackage.member(root, "actionview-8.1.4", "lib/action_view/helpers/asset_url_helper.rb")
proof[:framework] << metadata
%w[current_attributes environment_inquirer string_inquirer callbacks execution_context isolated_execution_state code_generator].each do |name|
  _, metadata = FidelitySourcePackage.member(root, "activesupport-8.1.4", "lib/active_support/#{name}.rb")
  proof[:framework] << metadata
end
compute = select.call(framework.fetch("lib/propshaft/helper.rb"), :compute_asset_path).gsub('Rails.application.assets.resolver', '@resolver').gsub('MissingAssetError.new', 'Propshaft::MissingAssetError.new')
# Original framework view: only its platform assembly collaborator is explicit.
original = <<~RUBY
  require 'propshaft'
  require 'action_view'
  require 'fast_blank'
  require_relative 'original_request_ember_assets'
  module OriginalRequestResolverHelper
    #{compute}
  end
  class OriginalRequestAssetView
    include ActionView::Helpers::AssetUrlHelper
    include OriginalRequestResolverHelper
    attr_reader :config
    def initialize(resolver, settings)
      @resolver = resolver
      @config = settings
    end
  end
  module OriginalRequestAssetBindings
    class << self; attr_accessor :view, :settings; end
  end
  module OriginalRequestAssetHelpers
    EmberAssets = OriginalAssetLifecycle::EmberAssets
    module GlobalSetting
      def self.use_s3?; OriginalRequestAssetBindings.settings.use_s3?; end
      def self.cdn_url; OriginalRequestAssetBindings.settings.cdn_url; end
      def self.s3_cdn_url; OriginalRequestAssetBindings.settings.s3_cdn_url; end
      def self.s3_asset_cdn_url; OriginalRequestAssetBindings.settings.s3_asset_cdn_url; end
    end
    module ActionController
      class Base
        def self.helpers; OriginalRequestAssetBindings.view; end
        def self.config; OriginalRequestAssetBindings.settings; end
      end
    end
    #{original_urls.join("\n")}
    #{original_map}
    def theme_js_assets
      @events << 'theme_compiler_version_acquisition'
      OriginalCompilerHelpers.instance_method(:theme_js_assets).bind(self).call
    end
  end
RUBY
File.write(File.join(build, "original_request_asset_helpers.rb"), original)
# Lift only the previous explicit boundary, preserving all real Theme reads,
# callbacks, cache computation and strict Array/schema/publication guards.
array = File.join(build, "native_theme_array_context.rb")
text = File.read(array)
anchor = "raise HtmlRenderingBoundary, 'actual Theme extra_js Array cache acquired; remaining import-map asset graph pending'"
raise "Array boundary changed" unless text.scan(anchor).size == 1
File.write(array, text.sub(anchor, 'value'))
proof[:transformations] = ["Concrete read-only serving root is bound explicitly after full pinned-source provenance audit", "Original initializer root/version expressions evaluated with live application configuration", "No-plugin empty loops fold only after actual registry check; external theme imports/stubs retained", "Full original plugin_js partial; actual file-backed Propshaft resolver and original AssetUrlHelper third reference", "Only previous Theme Array pre-dispatch boundary lifts; no new PG effects permitted"]
File.write(File.join(build, "request-assets-source-proof.json"), JSON.pretty_generate(proof) + "\n")

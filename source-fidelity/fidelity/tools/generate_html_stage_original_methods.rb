# frozen_string_literal: true
# Generate ISOLATED original methods, never a Rails app/HTML reference request.
require "prism"
require "json"
require "digest"
require "open3"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
spans = []
framework_sources = %w[lib/action_dispatch/http/mime_type.rb lib/action_dispatch/http/mime_types.rb].map do |member|
  _bytes, proof = FidelitySourcePackage.member(root, "actionpack-8.1.4", member)
  proof
end
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "original method source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  text
end
select = lambda do |path, name|
  found = []
  walk = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(Prism.parse(read.call(path)).value)
  raise "original method changed #{path}:#{name}" unless found.length == 1
  node = found.first
  spans << {source: path, name: name, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
upcoming_names = %i[statuses change_metadata meets_or_exceeds_status? change_status_value change_status exists?
  owning_plugin_configurable? requires_plugin_enabled? owning_plugin_enabled? change_dependencies_met? enabled?]
upcoming = upcoming_names.map { |name| select.call("lib/upcoming_changes.rb", name) }.join("\n")
defaults = %i[initialize load_setting activate_upcoming_change_override all_clean all get].map { |name| select.call("lib/site_settings/defaults_provider.rb", name) }.join("\n")
defaults_owner = Prism.parse(read.call("lib/site_settings/defaults_provider.rb")).value.statements.body.grep(Prism::ClassNode).first
constants = defaults_owner.body.body.grep(Prism::ConstantWriteNode).select { |node| %i[DEFAULT_LOCALE DEFAULT_LOCALE_SYM].include?(node.name) }.map(&:slice).join("\n")
raise "default locale constants changed" unless constants.include?('DEFAULT_LOCALE = "en"') && constants.include?('DEFAULT_LOCALE_SYM = :en')
preloader = %i[initialize store_preloaded].map { |name| select.call("lib/application_layout_preloader.rb", name) }.join("\n")
marker = select.call("app/controllers/application_controller.rb", :preload_json)
output = <<~RUBY
  # frozen_string_literal: true
  require "set"
  require "active_support/core_ext/object/blank"
  require "fast_blank"
  require "action_dispatch/http/mime_type"
  require "action_dispatch/http/mime_types"
  #{read.call("lib/enum.rb")}
  module OriginalHtmlStageSource
    class DefaultsProvider
      #{constants}
      #{defaults}
      alias [] get
    end
    module UpcomingChanges
      #{upcoming}
      class << self
        attr_accessor :live_provider
        def settings_provider; live_provider; end
      end
    end
    class Preloader
      #{preloader}
      def values; @preloaded; end
    end
    class Marker
      def initialize(request); @request = request; end
      def request; @request; end
      #{marker}
      def value; @_preloaded; end
    end
  end
RUBY
output += File.read(File.join(root, "fidelity/test/html_stage_original_context.rb"))
File.write(ARGV.fetch(0), output)
File.write(ARGV.fetch(0) + ".json", JSON.pretty_generate({pin: pin, actual_actionpack_mime_sources: framework_sources, selected_original_method_spans: spans,
  context: "fresh genuinely acquired portable-store values and source declarations; isolated original method protocols, NOT full original SiteSetting initialization/HTML request",
  generated_sha256: Digest::SHA256.hexdigest(output), original_html_request_invoked: false, html200_accepted: false}) + "\n")

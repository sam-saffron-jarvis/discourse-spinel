# frozen_string_literal: true
require 'prism'
require 'json'
require 'digest'
require 'open3'
require_relative 'source_package'
root = File.expand_path('../..', __dir__)
build = ARGV.fetch(0)
pin = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
proof = {pin: pin, sources: {}, spans: [], framework: [], page_accepted: false}
read = lambda do |path|
  source, status = Open3.capture2('git', '-C', File.join(root, 'discourse'), 'show', "#{pin}:#{path}")
  raise "client setup source changed #{path}" unless status.success? && source.b == File.binread(File.join(root, 'discourse', path))
  proof[:sources][path] = Digest::SHA256.hexdigest(source)
  source
end
select = lambda do |source, name|
  nodes = []
  visit = lambda do |node|
    nodes << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "client setup method ambiguous #{name}" unless nodes.size == 1
  node = nodes.first
  proof[:spans] << {method: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
tag, metadata = FidelitySourcePackage.member(root, 'actionview-8.1.4', 'lib/action_view/helpers/tag_helper.rb')
proof[:framework] << metadata
builder = select.call(tag, :tag_builder).slice.sub('def tag_builder', 'def source_setup_tag_builder')
initialize_node = select.call(tag, :initialize)
File.write(File.join(build, 'client_setup_builder_source.rb'), <<~RUBY)
  class ClientSetupTagBuilder
    #{initialize_node.slice}
    def owned_by?(view); @view_context.equal?(view); end
    def meta(id:, data:); raise ArgumentError, 'client setup meta serialization acquisition pending'; end
  end
  module ClientSetupBuilderSource
    #{builder.gsub('TagBuilder.new(self)', 'ClientSetupTagBuilder.new(self)')}
  end
RUBY
helper = select.call(read.call('app/helpers/application_helper.rb'), :client_side_setup_data)
assignment = helper.body.body.first
raise 'client setup first hash changed' unless assignment.is_a?(Prism::LocalVariableWriteNode) && assignment.value.is_a?(Prism::HashNode)
entries = assignment.value.elements
last = entries.index { |entry| entry.key.is_a?(Prism::SymbolNode) && entry.key.unescaped == 'asset_version' }
raise 'client setup asset-version order changed' unless last
captured = entries.first(last + 1).map do |entry|
  key = entry.key.unescaped
  value = entry.value.slice
  value = value.sub('Rails.configuration.action_controller.asset_host', 'settings.asset_host').sub('Rails.env', "ENV.fetch('RAILS_ENV')").sub('LetterAvatar.version', 'PortableLetterAvatarVersion.version').sub('Discourse.assets_digest', 'ClientSetupReadBootstrap.asset_version')
  text = entry.slice
  offset = entry.value.location.start_offset - entry.location.start_offset
  text[offset, entry.value.location.length] = "ClientSetupReadBootstrap.record_input(:#{key}, (#{value}))"
  text
end
File.write(File.join(build, 'client_setup_prefix_source.rb'), "module ClientSetupPrefixSource\ndef source_client_side_setup_data\nsetup_data = {\n#{captured.join(",\n")}\n}\nraise 'client setup asset-version boundary unexpectedly returned'\nend\nend\n")
# Third reference uses complete original helper; pure collaborators acquire
# live config, actual environment and original read-only avatar version inputs.
letter = read.call('lib/letter_avatar.rb')
letter_methods = %i[version vips_version font_version font_path macos?].map { |name| select.call(letter, name).slice }
version_line = letter.lines.find { |line| line.strip.start_with?('VIPS_VERSION = ') }.strip
raise 'avatar source constant missing' unless version_line
original_helper = helper.slice.sub('def client_side_setup_data', 'def source_client_side_setup_data')
# Observation wrappers do not alter supplied values or return partial setup.
original_entries = entries.first(last + 1).map do |entry|
  text = entry.slice
  offset = entry.value.location.start_offset - entry.location.start_offset
  text[offset, entry.value.location.length] = "ClientSetupReadBootstrap.record_input(:#{entry.key.unescaped}, (#{entry.value.slice}))"
  [entry.location.start_offset - helper.location.start_offset, entry.location.length, text]
end
original_entries.reverse_each { |offset, length, text| original_helper[offset + ('source_'.length), length] = text }
File.write(File.join(build, 'original_client_setup_source.rb'), <<~RUBY)
  require 'discourse_fonts'
  module OriginalClientSetupAvatar
    #{version_line}
    DISCOURSE_FONT_PATH = File.join(DiscourseFonts.path_for_fonts, 'NotoSans-Regular.woff2')
    module GlobalSetting
      def self.enable_vips_image_processing; ListHeadImages.configuration.value('enable_vips_image_processing'); end
    end
    module DiscourseVips
      def self.version; PortableAvatarVipsVersion.vips_version_string; end
    end
    class << self
      #{letter_methods.join("\n")}
      private :font_version, :font_path, :macos?
    end
  end
  module OriginalClientSetupHelpers
    module Rails
      def self.configuration; ClientSetupReadBootstrap; end
      def self.env; ActiveSupport::EnvironmentInquirer.new(ENV.fetch('RAILS_ENV')); end
    end
    LetterAvatar = OriginalClientSetupAvatar
    module Discourse
      def self.base_url; ::Discourse.base_url; end
      def self.base_path; ::Discourse.base_path; end
      def self.assets_digest; ClientSetupReadBootstrap.asset_version; end
    end
    #{original_helper}
  end
RUBY
_, font_metadata = FidelitySourcePackage.member(root, 'discourse-fonts-0.0.19', 'vendor/assets/fonts/NotoSans-Regular.woff2')
proof[:framework] << font_metadata
read.call('config/environments/development.rb')
raise 'development asset host binding changed' unless proof[:sources].key?('config/environments/development.rb') && File.read(File.join(root, 'discourse/config/environments/development.rb')).include?('config.action_controller.asset_host = GlobalSetting.cdn_url')
proof[:prefix_keys] = entries.first(last + 1).map { |entry| entry.key.unescaped }
proof[:transformations] = ['Actual source tag_builder lazy owner identity; native concrete builder stores current view, unsupported meta serialization refuses', 'Candidate exact initial setup Hash prefix preserves order and never returns partial data; asset-version acquisition refuses before missing MessageBus lifecycle', 'Original complete setup helper + original avatar/version/font computation on existing read-only library capability, no worker spawn', 'Development config.asset_host bound from actual source cdn_url; observer records values but returns original objects']
File.write(File.join(build, 'client-setup-prefix-source-proof.json'), JSON.pretty_generate(proof) + "\n")

# frozen_string_literal: true
# Source declarations and isolated original head helpers; never initializes Rails.
require "prism"
require "json"
require "digest"
require "open3"
require_relative "source_package"
root = File.expand_path("../..", __dir__)
app, build = ARGV
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
proof = {pin: pin, original: {}, spans: [], framework: [], html200_accepted: false}
read = lambda do |path|
  text, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "head source changed #{path}" unless status.success? && text.b == File.binread(File.join(root, "discourse", path))
  proof[:original][path] = Digest::SHA256.hexdigest(text)
  text
end
select = lambda do |text, name, path|
  found = []
  walk = lambda do |node|
    found << node if node.is_a?(Prism::DefNode) && node.name == name
    node.compact_child_nodes.each { |child| walk.call(child) }
  end
  walk.call(Prism.parse(text).value)
  raise "head method ambiguous #{path}:#{name}" unless found.size == 1
  node = found.first
  proof[:spans] << {source: path, name: name, start: node.location.start_offset, end: node.location.end_offset, sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
icon = read.call("lib/site_icon_manager.rb")
# This is pinned declaration data, not an observed upload/cache response.
assignments = Prism.parse(icon).value.statements.body.first.body.body
constants = assignments.grep(Prism::ConstantWriteNode).to_h { |node| [node.name, node.value.slice] }
infos = eval(constants.fetch(:ICONS), binding, "pinned ICONS declaration")
infos = infos.select { |key, _| %i[opengraph_image favicon apple_touch_icon].include?(key) }
raise "unsafe icon declaration" unless infos.size == 3 && infos.values.all? { |info| !info[:resize_required] }
native_infos = infos.to_h { |key, info| [key.to_s, info.merge(settings: info[:settings].map(&:to_s))] }
sketch = Integer(constants.fetch(:SKETCH_LOGO_ID))
routes = read.call("config/routes.rb")
feed = routes.match(/^\s*get "([^"]+)" => "list#latest_feed", :format => :rss$/)
raise "RSS route changed" unless feed
mime_source, metadata = FidelitySourcePackage.member(root, "actionpack-8.1.4", "lib/action_dispatch/http/mime_types.rb")
proof[:framework] << metadata
mime = mime_source.match(/^Mime::Type.register "([^"]+)", :rss$/)
raise "RSS MIME missing" unless mime
constants_text = "module ListHeadSource\nICON_INFO = #{native_infos.inspect}\nSKETCH_LOGO_ID = #{sketch}\nLATEST_FEED_PATH = #{('/' + feed[1]).inspect}\nRSS_MIME = #{mime[1].inspect}\nend\n"
File.write(File.join(build, "list_head_source.rb"), constants_text)
helper = read.call("app/helpers/application_helper.rb")
safety, metadata = FidelitySourcePackage.member(root, "actionview-8.1.4", "lib/action_view/helpers/output_safety_helper.rb")
proof[:framework] << metadata
raw = select.call(safety, :raw, "action_view/helpers/output_safety_helper.rb")
methods = %i[crawlable_meta_data generate_twitter_card_metadata get_absolute_image_url gsub_emoji_to_unicode].map { |name| select.call(helper, name, "app/helpers/application_helper.rb") }
asset, metadata = FidelitySourcePackage.member(root, "actionview-8.1.4", "lib/action_view/helpers/asset_tag_helper.rb")
proof[:framework] << metadata
rss = select.call(asset, :auto_discovery_link_tag, "action_view/helpers/asset_tag_helper.rb")
tag_source, metadata = FidelitySourcePackage.member(root, "actionview-8.1.4", "lib/action_view/helpers/tag_helper.rb")
proof[:framework] << metadata
read.call("app/models/site_setting.rb")
read.call("lib/global_path.rb")
read.call("lib/url_helper.rb")
original = <<~RUBY
  module OriginalListHeadHelpers
    module Template
      module Types
        def self.[](key)
          raise "unsupported original RSS MIME" unless key == :rss
          ListHeadSource::RSS_MIME
        end
      end
    end
    module GlobalSetting
      def self.relative_url_root; ListHeadImages.configuration.value("relative_url_root"); end
    end
    #{raw}
    #{methods.join("\n")}
    #{rss}
  end
  module OriginalListIcons
    SKETCH_LOGO_ID = #{sketch}
    module SiteSetting
      def self.get(name); ListHeadImages.upload(name.to_s); end
    end
    def self.full_cdn_url(url); ListHeadImages.full_cdn_url(url); end
    #{select.call(icon, :resolve_original, "lib/site_icon_manager.rb")}
    #{select.call(icon, :get_set_cache, "lib/site_icon_manager.rb")}
  end
RUBY
# Expand the two original define_singleton_method bodies with their exact captured
# declaration values. No cache value, upload ID or computed URL is supplied.
block_source = icon[/^  ICONS.each do \|name, info\|\n(.*?)\n  end\n/m, 1]
raise "icon getter source missing" unless block_source
original << "module OriginalListIcons\nICONS = #{infos.inspect}\nICONS.each do |name, info|\n#{block_source}\nend\nend\n"
# Select the actual legacy-tag call closure. Requiring all TagHelper also boots
# global inflections/I18n, incompatible with this deliberately isolated runtime.
# No applicable method is changed or replaced by the native renderer here.
constant_source = tag_source[tag_source.index("      BOOLEAN_ATTRIBUTES =")...tag_source.index("      PRE_CONTENT_STRINGS")]
tag_methods = [:tag, :tag_builder, :ensure_valid_html5_tag_name].map { |name| select.call(tag_source, name, "action_view/helpers/tag_helper.rb") }
builder_methods = [:initialize, :tag_options, :tag_option, :prefix_tag_option, :boolean_tag_option].map { |name| select.call(tag_source, name, "action_view/helpers/tag_helper.rb") }
original << "module OriginalHeadTagHelper\n#{constant_source}\nTagHelper = self\nclass TagBuilder\n#{builder_methods.join("\n")}\nend\n#{tag_methods.join("\n")}\nend\n"
# Initialization belongs at first helper use (the original lazy autoload point).
raise "invalid original head source" unless Prism.parse(original).success?
File.write(File.join(build, "original_list_head_helpers.rb"), original)
proof[:declarations] = native_infos
proof[:native_constants_sha256] = Digest::SHA256.hexdigest(constants_text)
proof[:transformations] = ["fixed local-store/CDN profile guarded from real configuration", "supported metadata call has only title/description kwargs; all other original branches absent", "original ICONS getter bodies expanded only with pinned declaration values", "optimized-image upload association binds its actual foreign key; SELECT only"]
File.write(File.join(build, "list-head-source-proof.json"), JSON.pretty_generate(proof) + "\n")

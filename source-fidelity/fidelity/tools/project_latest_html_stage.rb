# frozen_string_literal: true
# A fail-closed HTML controller stage. Never render HTML or acquire cold Site.
require "prism"
require "json"
require "digest"
require "open3"
root = File.expand_path("../..", __dir__)
app = ARGV.fetch(0)
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
spans = []
original_hashes = {}
read = lambda do |path|
  source = File.binread(File.join(root, "discourse", path))
  pinned, status = Open3.capture2("git", "-C", File.join(root, "discourse"), "show", "#{pin}:#{path}")
  raise "HTML source changed #{path}" unless status.success? && pinned.b == source
  original_hashes[path] = Digest::SHA256.hexdigest(source)
  source
end
select = lambda do |path, &predicate|
  source = read.call(path)
  nodes = []
  visit = lambda do |node|
    nodes << node if predicate.call(node)
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse(source).value)
  raise "HTML span changed #{path}" unless nodes.length == 1
  node = nodes.first
  spans << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node
end
method = lambda { |path, name| select.call(path) { |node| node.is_a?(Prism::DefNode) && node.name == name }.slice }
application = File.read(File.join(app, "app/controllers/application_controller.rb"))
# The original anonymous HTML guard is different from JSON's unconditional return.
profile = method.call("app/controllers/application_controller.rb", :redirect_to_profile_if_required)
original_guards = Prism.parse(profile).value.statements.body.first.body.body.take(2).map(&:slice)
raise "profile guards changed" unless original_guards == ["return if request.format.json?", "return if !current_user"]
app_ast = Prism.parse(application).value.statements.body.grep(Prism::ClassNode).first
old_profile = app_ast.body.body.grep(Prism::DefNode).find { |node| node.name == :redirect_to_profile_for_latest_json }
raise "missing projected profile callback" unless old_profile
application[old_profile.location.start_offset, old_profile.location.length] = "def redirect_to_profile_for_latest_json\n#{original_guards.join("\n")}\nraise ArgumentError, 'unsupported authenticated HTML profile redirect'\nend"
File.write(File.join(app, "app/controllers/application_controller.rb"), application)
# Preserve the existing typed request-env key translation in the theme consumer.
theme_helper = File.join(app, "app/models/theme_modifier_helper.rb")
File.write(theme_helper, File.read(theme_helper).gsub("[](:resolved_theme_id)", '[]("discourse.resolved_theme_id")'))
# Original request callbacks are retained by the existing request projection.
# The real constructor is already projected; add only the real storage method.
preloader = File.join(app, "app/models/application_layout_preloader.rb")
File.write(preloader, File.read(preloader).sub(/end\s*\z/) { "#{method.call("lib/application_layout_preloader.rb", :store_preloaded)}\nend\n" })
macro = select.call("app/controllers/list_controller.rb") do |node|
  node.is_a?(Prism::CallNode) && node.name == :define_method && node.arguments&.arguments&.first&.slice == "filter"
end
body = macro.block.body.slice.sub('TopicQuery.new(current_user, list_opts).public_send("list_#{filter}")', 'TopicQuery.new(current_user, list_opts).list_latest')
# All metadata remains. This is NOT the JSON action with MIME changed.
parsed = Prism.parse("def latest\n#{body}\nend").value.statements.body.first
shared = parsed.body.body.grep(Prism::IfNode).find { |node| node.predicate.slice == "guardian.can_create_shared_draft? && @category.present?" }
raise "HTML shared draft source changed" unless shared
body = body.sub(shared.slice, 'raise ArgumentError, "unsupported HTML shared-draft profile" if guardian.can_create_shared_draft?')
# set_category is declared only for categorized actions, never this /latest route.
# Preserve the default metadata branch without importing an impossible Category.
metadata_ast = Prism.parse("def latest\n#{body}\nend").value
category_nodes = []
walk_category = lambda do |node|
  category_nodes << node if node.is_a?(Prism::IfNode) && node.predicate.slice == "list_opts[:category] && @category"
  node.compact_child_nodes.each { |child| walk_category.call(child) }
end
walk_category.call(metadata_ast)
raise "HTML category metadata source changed" unless category_nodes.length == 1
category_node = category_nodes.first
body = body.sub(category_node.slice, category_node.subsequent.statements.slice)
body = body.sub("@category.blank? && ", "")
# Reuse actual source paging component (the source itself emits JSON paging URLs
# even for HTML); it is not a JSON response or JSON request admission.
body = body.gsub("construct_url_with(", "construct_latest_json_url_with(")
controller = File.read(File.join(app, "app/controllers/list_controller.rb"))
method.call("app/controllers/application_controller.rb", :current_homepage)
method.call("lib/topic_list_responder.rb", :localize_topic_list_content)
respond = select.call("lib/topic_list_responder.rb") { |node| node.is_a?(Prism::CallNode) && node.name == :html && node.receiver&.slice == "format" }
html_body = respond.block.body.slice
raise "HTML render boundary changed" unless html_body.end_with?('render "list/list"')
html_body = html_body.delete_suffix('render "list/list"') + 'raise HtmlRenderingBoundary, "unimplemented original list/list + application layout; cold real-data acquisition prohibited"'
# Same fixed serializer expansion as the already-proven JSON component, keeping
# the real HTML preloader key/storage and its script-closing safety transform.
html_body = html_body.sub('MultiJson.dump(TopicListSerializer.new(list, scope: guardian))', 'JSON.generate(TopicListSerializer.new(list, scope: guardian).as_json.as_json)')
latest = <<~RUBY
    def latest(options = nil)
      raise ArgumentError, "unsupported non-HTML stage" unless request.format == "html"
      filter = :latest
      #{body}
    end
RUBY
raise "projected latest wrapper changed" unless controller.include?("def latest\n  latest_json\nend")
controller = controller.sub("def latest\n  latest_json\nend", latest)
extra = <<~RUBY
    attr_reader :html_stage_list
    def respond_with_list(list)
      discourse_expires_in 1.minute
      @html_stage_list = list
      #{html_body}
    end
    def localize_topic_list_content(list)
      return if list.topics.blank? || !SiteSetting.content_localization_enabled
      raise ArgumentError, "unsupported HTML content localization profile"
    end
    #{method.call("app/controllers/application_controller.rb", :store_preloaded)}
    def current_homepage
      raise ArgumentError, "unsupported authenticated HTML homepage" unless current_user.nil?
      HomepageHelper.resolve(request, nil)
    end
    def feed_route_exists?(filter)
      raise ArgumentError, "unsupported HTML feed filter" unless filter == :latest
      !latest_feed_path.empty?
    end
RUBY
controller = controller.sub(/end\s*\z/, "#{extra}\nend\n")
File.write(File.join(app, "app/controllers/list_controller.rb"), controller)
File.write(File.join(app, "app/models/html_rendering_boundary.rb"), "class HtmlRenderingBoundary < StandardError; end\n")
# Same original overload algorithm, under the newly explicit /latest profile.
overload = File.join(app, "app/models/overload_protections_request_reads.rb")
File.write(overload, File.read(overload).gsub('env["PATH_INFO"] == "/latest.json"', 'env["PATH_INFO"] == "/latest"'))
# Read-only homepage resolution is required by the ORIGINAL HTML metadata.
# No custom homepage/registered plugin availability callbacks are admitted.
homepage = method.call("lib/homepage_helper.rb", :resolve)
homepage = homepage.sub('return custom_homepage_route(request)', 'raise ArgumentError, "unsupported custom HTML homepage"')
homepage = homepage.sub('return custom_homepage_route(request) if enabled', 'raise ArgumentError, "unsupported plugin HTML homepage" if enabled')
File.write(File.join(app, "app/models/homepage_helper.rb"), <<~RUBY)
  class HomepageHelper
    #{homepage}
    def self.option_available?(homepage, request, current_user)
      raise ArgumentError, "unsupported registered HTML homepage options" unless DiscoursePluginRegistry.homepage_options.empty?
      true
    end
    def self.top_menu_homepage(current_user)
      raise ArgumentError, "unsupported HTML top-menu fallback"
    end
  end
RUBY
# Keep actual registry initialization, not an invented empty registry.
registry = File.join(app, "app/models/discourse_plugin_registry.rb")
method.call("lib/discourse_plugin_registry.rb", :define_register)
method.call("lib/discourse_plugin_registry.rb", :define_filtered_register)
select.call("lib/discourse_plugin_registry.rb") { |node| node.is_a?(Prism::CallNode) && node.name == :define_filtered_register && node.arguments&.arguments&.first&.slice == ":homepage_options" }
registry_extra = <<~RUBY
    def self.html_default_modifiers_present?
      return false unless @modifiers
      callbacks = @modifiers[:site_setting_defaults]
      callbacks && !callbacks.empty?
    end
    def self._raw_homepage_options
      @homepage_options ||= Array.new
    end
    def self.homepage_options
      _raw_homepage_options.filter_map { |h| h[:value] if h[:plugin].enabled? }.uniq
    end
    def self.register_homepage_option(value, plugin)
      _raw_homepage_options << {plugin: plugin, value: value}
    end
RUBY
File.write(registry, File.read(registry).sub(/end\s*\z/, "#{registry_extra}\nend\n"))
# Actual source status ranks; no effective setting/observed enabled flag.
status_method = method.call("lib/upcoming_changes.rb", :statuses)
status_ast = Prism.parse(status_method).value
status_call = nil
find_status = lambda do |node|
  status_call = node if node.is_a?(Prism::CallNode) && node.name == :new && node.receiver&.slice == "::Enum"
  node.compact_child_nodes.each { |child| find_status.call(child) }
end
find_status.call(status_ast)
raise "upcoming status source changed" unless status_call
File.write(File.join(app, "app/models/html_upcoming_statuses.rb"), "class HtmlUpcomingStatuses\nVALUES = {#{status_call.arguments.arguments.first.slice}}.freeze\nend\n")
method.call("lib/upcoming_changes.rb", :enabled?)
method.call("lib/upcoming_changes.rb", :change_dependencies_met?)
method.call("lib/site_settings/defaults_provider.rb", :all)
# Necessary original special getters, driven by the LIVE settings store.
# A configured enum override is a separate unsupported profile, never forced off.
method.call("app/models/site_setting.rb", :homepage)
settings = File.join(app, "app/models/site_setting_request_reads.rb")
settings_extra = <<~RUBY
  def self.top_menu(scoped_to = nil)
    raise ArgumentError, "unsupported scoped HTML menu" unless scoped_to.nil?
    raise ArgumentError, "unsupported HTML settings-default modifier profile" if DiscoursePluginRegistry.html_default_modifiers_present?
    portable_store.get_top_menu_for_html(portable_site, HtmlUpcomingStatuses::VALUES)
  end
  def self.homepage
    configured = default_homepage.presence
    raise ArgumentError, "unsupported configured HTML homepage enum" if configured
    top_menu_items[0].name
  end
  #{method.call("app/models/site_setting.rb", :top_menu_items)}
  #{method.call("app/models/site_setting.rb", :anonymous_menu_items)}
  #{method.call("app/models/site_setting.rb", :anonymous_homepage)}
RUBY
File.write(settings, File.read(settings).sub(/end\s*\z/, "#{settings_extra}\nend\n"))
File.write(File.join(app, "app/models/top_menu_item.rb"), read.call("app/models/top_menu_item.rb"))
# Actual filter declarations and actual RSS route, needed by HTML metadata.
discourse = File.join(app, "app/models/discourse_controller_reads.rb")
File.write(discourse, File.read(discourse).sub(/end\s*\z/, "#{method.call("lib/discourse.rb", :anonymous_filters)}\nend\n"))
routes = File.join(app, "config/routes.rb")
raise "source RSS route changed" unless read.call("config/routes.rb").include?('get "latest.rss" => "list#latest_feed", :format => :rss')
File.write(routes, File.read(routes).sub("\nend", "\n get '/latest.rss', to: 'list#latest_feed', format: :rss, as: :latest_feed\nend"))
File.write(File.join(app, "html-stage-source.json"), JSON.pretty_generate({pin: pin, original_source_sha256: original_hashes, spans: spans,
  transformations: [
    "Original fixed latest action, actual query/metadata/responder branch; no JSON response/MIME relabeling",
    "Only source-proven uncategorized /latest metadata branch selected; shared drafts refuse",
    "Reuse original paging algorithm (original HTML also emits JSON paging URLs)",
    "Actual RSS route URL helper supplies feed availability; full Rails route-set reflection not claimed",
    "Anonymous profile redirect guard retained; configured/custom/plugin homepage and enabled localization refuse",
    "Original source constructor/storage retained; accepted fixed serializer bridge supplies fresh genuine list JSON",
    "Existing native theme env-slot translation preserved for original ThemeModifierHelper",
    "Top-menu upcoming default read from live stored opt-out/promotion/source metadata; no activation callbacks replaced or full settings lifecycle claimed",
    "Original render call replaced by explicit refusal BEFORE execution, not canned HTML; after-render callbacks remain unexecuted"
  ],
  generated_stage_sha256: %w[app/controllers/application_controller.rb app/controllers/list_controller.rb
    app/models/application_layout_preloader.rb app/models/theme_modifier_helper.rb app/models/homepage_helper.rb
    app/models/discourse_plugin_registry.rb app/models/site_setting_request_reads.rb app/models/top_menu_item.rb
    app/models/discourse_controller_reads.rb app/models/html_upcoming_statuses.rb config/routes.rb].to_h { |path| [path, Digest::SHA256.file(File.join(app, path)).hexdigest] },
  homepage_reader_sha256: Digest::SHA256.file(File.join(root, "fidelity/compat/discourse/lib/site_settings/portable_html_homepage_readers.rb")).hexdigest,
  stage: "HTML ingress/controller/query/derived list preload, explicit refusal before original rendering",
  supplied_production_preloads: false, original_html_request: false, html200_accepted: false, page_accepted: false}) + "\n")

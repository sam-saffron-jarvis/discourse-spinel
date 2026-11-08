# frozen_string_literal: true
# Bounded controller READ experiment. This does not admit omitted middleware/
# callbacks: full request acceptance must compare them before becoming true.
require "prism"
require "json"
require "digest"
require "fileutils"
reference, candidate, output = ARGV
parts = []
generated = {}
read = lambda do |name, patched = false|
  File.binread(File.join(patched ? candidate : reference, name))
end
owner_for = lambda do |text|
  Prism.parse(text).value.statements.body.find { |node| node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) }
end
method_for = lambda do |path, name, patched = false|
  source = read.call(path, patched)
  definitions = []
  visit = lambda do |node|
    if node.is_a?(Prism::DefNode)
      definitions << node
    else
      node.compact_child_nodes.each { |child| visit.call(child) }
    end
  end
  visit.call(Prism.parse(source).value)
  node = definitions.find { |method| method.name == name }
  raise "missing request method #{path}:#{name}" unless node
  parts << {source: path, candidate: patched, source_sha256: Digest::SHA256.hexdigest(source),
    start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
write = lambda do |name, text|
  raise "invalid controller read component #{name}" unless Prism.parse(text).success?
  path = File.join(output, name)
  FileUtils.mkdir_p(File.dirname(path))
  normalized = text.gsub(/^[ \t]+$/, "")
  File.write(path, normalized)
  generated[name] = Digest::SHA256.hexdigest(normalized)
end

# Real default actor and CurrentUser methods, not nil-returning stand-ins.
path = "lib/auth/default_current_user_provider.rb"
source = read.call(path, true)
owner = owner_for.call(source)
constants = owner.body.body.grep(Prism::ConstantWriteNode).select { |node| %i[CURRENT_USER_KEY USER_TOKEN_KEY DECRYPTED_AUTH_COOKIE API_KEY_ENV USER_API_KEY_ENV TOKEN_COOKIE PATH_INFO HEADER_API_KEY USER_API_KEY].include?(node.name) }.map(&:slice)
actor = "class Auth::DefaultCurrentUserProvider\n" + (constants + %i[initialize current_user is_api? is_user_api? refresh_session_for_latest_json find_v1_auth_cookie_for_latest_json].map { |name| method_for.call(path, name, true) }).join("\n\n") + "\ndef refresh_session(user, session, cookie_jar)\n refresh_session_for_latest_json(user, session, cookie_jar)\nend\nend\n"
# Namespace comes from the actual original declaration; no fake Auth surface.
auth = File.binread(File.join(reference, "lib/auth.rb"))
write.call("app/models/auth.rb", owner_for.call(auth).slice + "\n")
write.call("app/models/default_current_user_provider.rb", actor)
overload_path = "lib/middleware/overload_protections.rb"
overload = %i[initialize call_latest_json overloaded_for_latest_json? authenticated_request_for_latest_json? api_credentials_present?].map { |name| method_for.call(overload_path, name, true) }
processing_path = "lib/middleware/processing_request.rb"
processing_source = read.call(processing_path)
queue_constant = owner_for.call(processing_source).body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :REQUEST_QUEUE_SECONDS_ENV_KEY }
raise "actual queue env declaration changed" unless queue_constant
parts << {source: processing_path, candidate: false, source_sha256: Digest::SHA256.hexdigest(processing_source),
  start_byte: queue_constant.location.start_offset, end_byte: queue_constant.location.end_offset,
  text_sha256: Digest::SHA256.hexdigest(queue_constant.slice)}
overload.map! { |text| text.gsub("Middleware::ProcessingRequest::REQUEST_QUEUE_SECONDS_ENV_KEY", queue_constant.value.slice) }
write.call("app/models/overload_protections_request_reads.rb", "module Middleware\nclass OverloadProtections\n" + overload.join("\n\n") + "\ndef call(env)\n call_latest_json(env)\nend\nend\nend\n")
current = %i[current_user current_user_provider is_api? is_user_api? refresh_session].map { |name| method_for.call("lib/current_user.rb", name) }
write.call("app/models/current_user.rb", "module CurrentUser\n" + current.join("\n\n") + "\nend\n")
write.call("app/models/portable_controller_login_policy.rb", read.call("lib/portable_controller_login_policy.rb", true))
write.call("app/models/portable_git_version.rb", read.call("lib/portable_git_version.rb", true))
write.call("app/models/portable_readonly_state.rb", read.call("lib/portable_readonly_state.rb", true))
# Shared declaration file's require is relocated to its projected sibling.
write.call("app/models/portable_readonly_declarations.rb", read.call("lib/portable_readonly_declarations.rb", true))
json_error = %i[create_errors_json create_errors_array].map { |name| method_for.call("lib/json_error.rb", name, true) }
write.call("app/models/json_error.rb", "module JsonError\n" + json_error.join("\n\n") + "\nend\n")
getter = method_for.call("lib/discourse.rb", :current_user_provider)
discourse_source = read.call("lib/discourse.rb")
discourse_owner = owner_for.call(discourse_source)
errors = discourse_owner.body.body.grep(Prism::ClassNode).select { |node| %w[InvalidAccess InvalidParameters NotLoggedIn].include?(node.constant_path.slice) }.map(&:slice)
raise "actual request errors missing" unless errors.length == 3
write.call("app/models/discourse_controller_reads.rb", "module Discourse\n#{getter}\n#{errors.join("\n\n")}\nend\n")

# Actual parameter validators/option list and constructor, with the already
# verified shared list component behind the supported anonymous dispatcher.
query_methods = %i[validators validate? public_valid_options valid_options initialize].map { |name| method_for.call("lib/topic_query.rb", name) }
query_source = read.call("lib/topic_query.rb")
query_owner = owner_for.call(query_source)
query_constants = query_owner.body.body.grep(Prism::ConstantWriteNode).select { |node| %i[PG_MAX_INT].include?(node.name) }.map(&:slice)
delegate = <<~RUBY
  def list_latest
    raise ArgumentError, "unsupported authenticated latest request" unless @user.nil?
    options = @options.dup
    [:page, :per_page, :min_posts, :max_posts].each do |key|
      value = options[key]
      options[key] = value.to_i if value.is_a?(String)
    end
    TopicQueryListLatest.new(options).list_latest
  end
RUBY
write.call("app/models/topic_query_request_reads.rb", "class TopicQuery\n" + (query_constants + query_methods + [delegate]).join("\n\n") + "\nend\n")
params = method_for.call("lib/topic_query_params.rb", :build_topic_list_options, true)
write.call("app/models/topic_query_params.rb", "module TopicQueryParams\n#{params}\nend\n")

# Real shared-draft permission predicate and its source setting dependency.
permission = %i[can_create_shared_draft? can_see_shared_draft?].map { |name| method_for.call("lib/guardian/topic_guardian.rb", name) }
write.call("app/models/topic_guardian_request_reads.rb", "module TopicGuardian\n" + permission.join("\n\n") + "\nend\n")
setting = method_for.call("app/models/site_setting.rb", :shared_drafts_enabled?)
write.call("app/models/site_setting_request_reads.rb", "class SiteSetting < ActiveRecord::Base\n#{setting}\nend\n")

# Concrete JSON action/responder shared with genuine candidate Rails. The
# native route selects latest_json; it cannot execute the original HTML branch.
action = %i[latest_json respond_with_json_list construct_latest_json_url_with].map { |name| method_for.call("lib/portable_latest_json_action.rb", name, true) }
paging = %i[latest_json_next_page_params latest_json_prev_page_params latest_json_page_params].map { |name| method_for.call("lib/portable_latest_json_action.rb", name, true) }
# Fixed :latest is the action in this profile, not an arbitrary path helper.
action[2] = action[2].sub('public_send(method, opts.merge(page_params))', 'latest_path(opts.merge(page_params))')
wrapper = "def latest\n  latest_json\nend"
write.call("app/controllers/list_controller.rb", "class ListController < ApplicationController\n  include TopicQueryParams\n" + ([wrapper] + action + paging).join("\n\n") + "\nend\n")
application_methods = %i[guardian param_to_integer_list can_cache_content? discourse_expires_in
  bfcache_compatibility_mode? dont_cache_page ensure_dont_cache_page
  set_current_user_for_latest_json_logs set_current_user_header_for_latest_json_logs
  conditionally_allow_site_embedding preload_json spa_boot_request? is_feed_request? is_feed_response? add_noindex_header
  redirect_to_profile_for_latest_json clear_notifications_for_latest_json
  authorize_mini_profiler mini_profiler_enabled_for_latest_json?
  requires_login requires_login_arg block_if_requires_login ensure_logged_in perform_refresh_session
  redirect_to_login_for_latest_json set_crawler_header use_crawler_layout?
  handle_theme resolve_safe_mode initialize_application_layout_preloader_for_latest_json login_method_for_latest_json
  set_mp_snapshot_fields_for_latest_json render_latest_json_parameter_error]
application = application_methods.map { |name| method_for.call("app/controllers/application_controller.rb", name, true) }
# The same guarded JSON components are called by the full candidate callbacks.
application << "def set_current_user_for_logs\n set_current_user_for_latest_json_logs\nend"
application << "def set_current_user_header_for_logs\n set_current_user_header_for_latest_json_logs\nend"
application << "def mini_profiler_enabled?\n mini_profiler_enabled_for_latest_json?\nend"
# The real callback name executes the same shared component body. Keep yield
# directly in the around method so framework callback unwinding sees its scope.
application << method_for.call("app/controllers/application_controller.rb", :with_resolved_locale_for_latest_json, true)
application << method_for.call("app/controllers/application_controller.rb", :with_resolved_locale_for_latest_json, true).sub("def with_resolved_locale_for_latest_json", "def with_resolved_locale")
# This source has a preceding empty SiteSettings module and a qualified class.
defaults_class = Prism.parse(read.call("lib/site_settings/defaults_provider.rb")).value.statements.body.grep(Prism::ClassNode).first
default_locale = defaults_class.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :DEFAULT_LOCALE }
raise "source default locale constant changed" unless default_locale
parts << {source: "lib/site_settings/defaults_provider.rb", candidate: false,
  source_sha256: Digest::SHA256.hexdigest(read.call("lib/site_settings/defaults_provider.rb")),
  start_byte: default_locale.location.start_offset, end_byte: default_locale.location.end_offset,
  text_sha256: Digest::SHA256.hexdigest(default_locale.slice)}
write.call("app/models/defaults_provider_locale_constant.rb", "module SiteSettings\nclass DefaultsProvider\n#{default_locale.slice}\nend\nend\n")
application << method_for.call("lib/read_only_mixin.rb", :check_readonly_mode_for_latest_json, true)
application << method_for.call("lib/read_only_mixin.rb", :add_readonly_header)
application << "def check_readonly_mode\n check_readonly_mode_for_latest_json(PortableReadonlyContext.redis, PortableReadonlyContext.force?, PortableReadonlyContext.redis_error_at)\nend"
{
  set_mp_snapshot_fields: ["app/controllers/application_controller.rb", :set_mp_snapshot_fields_for_latest_json],
  initialize_application_layout_preloader: ["app/controllers/application_controller.rb", :initialize_application_layout_preloader_for_latest_json],
  redirect_to_login_if_required: ["app/controllers/application_controller.rb", :redirect_to_login_for_latest_json],
  redirect_to_profile_if_required: ["app/controllers/application_controller.rb", :redirect_to_profile_for_latest_json],
  clear_notifications: ["app/controllers/application_controller.rb", :clear_notifications_for_latest_json],
  block_if_readonly_mode: ["lib/read_only_mixin.rb", :block_if_readonly_mode_for_latest_json],
  block_if_archived: ["lib/archived_site_mixin.rb", :block_if_archived_for_latest_json],
  normalize_markdown_format: ["lib/markdown_endpoint/controller_support.rb", :normalize_markdown_format_for_latest_json],
  add_markdown_discovery_header: ["lib/markdown_endpoint/controller_support.rb", :add_markdown_discovery_header_for_latest_json],
}.each do |name, (path, component)|
  application << method_for.call(path, component, true) unless application_methods.include?(component)
  application << "def #{name}\n #{component}\nend"
end
# This declared request profile REQUIRES the real profiler5 component, loaded
# by the shared bootstrap before any request. Bind its actual class, not a
# captured enabled boolean or the optional full-server `defined?` initializer.
# Availability remains optional in full candidate Rails; profiler-less native
# requests are not an admitted profile.
application.map! { |text| text.gsub("MINI_PROFILER_CLASS", "Rack::MiniProfiler") }
application_source_constants = owner_for.call(read.call("app/controllers/application_controller.rb")).body.body.grep(Prism::ConstantWriteNode).select do |node|
  %i[NO_THEMES NO_PLUGINS NO_UNOFFICIAL_PLUGINS SAFE_MODE LEGACY_NO_THEMES LEGACY_NO_UNOFFICIAL_PLUGINS].include?(node.name)
end
raise "safe mode constants changed" unless application_source_constants.length == 6
application = application_source_constants.map(&:slice) + application
resolver = method_for.call("lib/theme_resolver.rb", :resolve_latest_json_theme_id, true)
write.call("app/models/theme_resolver_request_reads.rb", "module ThemeResolver\n#{resolver}\ndef self.resolve_theme_id(request, guardian, current_user)\n resolve_latest_json_theme_id(request, guardian, current_user)\nend\nend\n")
mobile = method_for.call("lib/mobile_detection.rb", :mobile_device?)
write.call("app/models/mobile_detection_request_reads.rb", "module MobileDetection\n#{mobile}\nend\n")
preloader = method_for.call("lib/application_layout_preloader.rb", :initialize)
write.call("app/models/application_layout_preloader.rb", "class ApplicationLayoutPreloader\n#{preloader}\nend\n")
# Preserve the real declarations and nesting order for these incremental
# callbacks. All remaining callbacks stay explicitly unaccepted in the manifest.
application_source = read.call("app/controllers/application_controller.rb", true)
callback_targets = %i[ensure_dont_cache_page set_current_user_for_logs preload_json
  conditionally_allow_site_embedding ensure_vary_header add_noindex_header
  block_if_readonly_mode block_if_archived authorize_mini_profiler clear_notifications redirect_to_profile_if_required
  block_if_requires_login redirect_to_login_if_required perform_refresh_session set_crawler_header
  handle_theme initialize_application_layout_preloader set_mp_snapshot_fields check_readonly_mode add_readonly_header with_resolved_locale]
application_owner = owner_for.call(application_source)
callback_lines = application_owner.body.body.grep(Prism::CallNode).select do |node|
  %i[before_action around_action after_action].include?(node.name) &&
    node.arguments&.arguments&.first && callback_targets.include?(node.arguments.arguments.first.slice.delete_prefix(":").to_sym)
end.map do |node|
  parts << {source: "app/controllers/application_controller.rb", candidate: true,
    source_sha256: Digest::SHA256.hexdigest(application_source), start_byte: node.location.start_offset,
    end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
raise "request callback declaration changed" unless callback_lines.length == callback_targets.length
# The genuine initializer includes this concern AFTER the application class,
# so append its declarations here as Rails does (including reverse after order).
markdown_source = read.call("lib/markdown_endpoint/controller_support.rb", true)
markdown_owner = owner_for.call(markdown_source).body.body.grep(Prism::ModuleNode).first
markdown_included = markdown_owner.body.body.grep(Prism::CallNode).find { |node| node.name == :included }
markdown_callbacks = markdown_included.block.body.body.grep(Prism::CallNode).select { |node| %i[before_action after_action].include?(node.name) }
raise "Markdown declarations changed" unless markdown_callbacks.length == 2
markdown_callbacks.each do |node|
  callback_lines << node.slice
  callback_targets << node.arguments.arguments.first.slice.delete_prefix(":").to_sym
  parts << {source: "lib/markdown_endpoint/controller_support.rb", candidate: true,
    source_sha256: Digest::SHA256.hexdigest(markdown_source), start_byte: node.location.start_offset,
    end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
end
crawler = method_for.call("lib/crawler_detection.rb", :crawler_layout_request_for_latest_json?, true)
write.call("app/models/crawler_detection_request_reads.rb", "module CrawlerDetection\n#{crawler}\ndef self.crawler_layout_request?(request)\n crawler_layout_request_for_latest_json?(request)\nend\nend\n")
# Same outer exception boundary as original Rails; do not swallow errors in
# the action and then accidentally run after filters or render in wrong locale.
parameter_rescue = "rescue_from Discourse::InvalidParameters do |error|\n render_latest_json_parameter_error(error)\nend"
callback_lines.unshift(parameter_rescue)
vary = method_for.call("lib/vary_header.rb", :ensure_vary_header)
write.call("app/models/vary_header_request_reads.rb", "module VaryHeader\n#{vary}\nend\n")
write.call("app/controllers/application_controller.rb", "class ApplicationController < ActionController::Base\n include CurrentUser\n include JsonError\n include VaryHeader\n" + callback_lines.join("\n") + "\n" + application.join("\n\n") + "\nend\n")
cache = read.call("lib/middleware/anonymous_cache.rb")
# The real method only records a request env duration; no cache is fabricated.
cache_node = owner_for.call(cache).body.body.grep(Prism::ClassNode).first.body.body.grep(Prism::DefNode).find { |node| node.name == :anon_cache }
raise "anonymous cache duration source changed" unless cache_node
write.call("app/models/anonymous_cache_request_reads.rb", "module Middleware\n class AnonymousCache\n#{cache_node.slice}\n end\nend\n")
# Preserve the application's actual middleware deletion, not a header-driven
# approximation of Rack::ETag (which DOES digest no-store responses by default).
policy_source = read.call("config/application.rb")
policy_nodes = []
visit = lambda do |node|
  policy_nodes << node if node.is_a?(Prism::CallNode) && node.slice == "config.middleware.delete Rack::ETag"
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse(policy_source).value)
raise "actual Rack::ETag deletion changed" unless policy_nodes.length == 1
node = policy_nodes.first
parts << {source: "config/application.rb", candidate: false, source_sha256: Digest::SHA256.hexdigest(policy_source),
  start_byte: node.location.start_offset, end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}
write.call("app/models/portable_request_middleware_policy.rb", "class PortableRequestMiddlewarePolicy\n def self.etag_middleware?\n false\n end\nend\n")
File.write(File.join(output, "config/routes.rb"), "Rails.application.routes.draw do\n get '/latest', to: 'list#latest', as: :latest\nend\n")
File.write(File.join(output, "request-read-components.json"), JSON.pretty_generate({profile: "bounded genuine controller JSON experiment, NOT complete callbacks/middleware acceptance", parts: parts,
  projected_callback_declarations: callback_targets,
  generated_sha256: generated, omitted_callbacks_or_middleware_accepted: false, captured_outputs_as_inputs: false, json_request_accepted: false}) + "\n")

# frozen_string_literal: true
# Fixed latest action expansion and explicitly guarded no-credentials actor.
# Original sources stay immutable; this is shared candidate application code.
require "prism"
require "json"
require "digest"
require "fileutils"
require "open3"
root = File.expand_path("../..", __dir__)
reference = File.join(root, "discourse")
candidate = File.join(root, "fidelity/compat/discourse")
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
lock_path = File.join(root, "fidelity/SOURCE_LOCK.json")
lock = JSON.parse(File.read(lock_path))
inputs = {}
changes = []
outputs = {}
read = lambda do |path|
  source, status = Open3.capture2("git", "-C", reference, "show", "#{pin}:#{path}")
  raise "missing pinned request source #{path}" unless status.success?
  source = source.b
  raise "reference request source changed #{path}" unless File.binread(File.join(reference, path)) == source
  sha = Digest::SHA256.hexdigest(source)
  inputs[path] = sha
  copied = File.join(root, "fidelity/source/discourse", path)
  raise "immutable request copy changed #{path}" if File.exist?(copied) && File.binread(copied) != source
  FileUtils.mkdir_p(File.dirname(copied))
  File.binwrite(copied, source) unless File.exist?(copied)
  old = lock["files"].find { |item| item["path"] == path }
  raise "request source lock changed #{path}" if old && old["sha256"] != sha
  lock["files"] << {"path" => path, "sha256" => sha} unless old
  source
end
write = lambda do |path, source|
  raise "invalid shared request source #{path}" unless Prism.parse(source).success?
  output = File.join(candidate, path)
  FileUtils.mkdir_p(File.dirname(output))
  File.binwrite(output, source)
  outputs[path] = Digest::SHA256.hexdigest(source)
end
record = lambda do |path, node, reason|
  changes << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice), reason: reason}
end

path = "app/controllers/list_controller.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
loop_node = owner.body.body.grep(Prism::CallNode).find { |node| node.name == :each && node.receiver&.slice == "Discourse.filters" }
raise "filter action declaration changed" unless loop_node
macro = loop_node.block.body.body.grep(Prism::CallNode).find { |node| node.name == :define_method && node.arguments&.arguments&.first&.slice == "filter" }
raise "latest action body changed" unless macro&.block
body = macro.block.body.slice
send = 'TopicQuery.new(current_user, list_opts).public_send("list_#{filter}")'
raise "latest query dispatch changed" unless body.include?(send)
body = body.sub(send, "TopicQuery.new(current_user, list_opts).list_latest")
# The metadata has no JSON consumer: keep it for HTML but avoid importing the
# HTML/homepage/feed dependency family into a JSON-only compilation boundary.
metadata = "if Discourse.anonymous_filters.include?(filter)"
raise "latest page metadata source changed" unless body.include?(metadata)
body = body.sub(metadata, "if !request.format.json? && Discourse.anonymous_filters.include?(filter)")
# Keep the HTML action available through super; JSON executes a separately
# named shared component so the native request closure need not import HTML.
parsed_body = Prism.parse("def latest(options = nil)\nfilter = :latest\n#{body}\nend").value.statements.body.first
metadata_node = parsed_body.body.body.grep(Prism::IfNode).find { |node| node.predicate.slice.include?("Discourse.anonymous_filters.include?(filter)") }
raise "JSON metadata decomposition changed" unless metadata_node
json_body = body.sub(metadata_node.slice, "")
shared_drafts_node = parsed_body.body.body.grep(Prism::IfNode).find { |node| node.predicate.slice == "guardian.can_create_shared_draft? && @category.present?" }
raise "shared draft action source changed" unless shared_drafts_node
json_body = json_body.sub(shared_drafts_node.slice, 'raise ArgumentError, "unsupported shared-draft JSON request profile" if guardian.can_create_shared_draft?')
json_body = json_body.gsub("construct_url_with(", "construct_latest_json_url_with(")
json_body = json_body.sub("respond_with_list(list)", "respond_with_json_list(list)")
url_node = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :construct_url_with }
url_source = url_node.slice.dup
unicode_branches = url_node.body.body.grep(Prism::IfNode).select { |node| node.predicate.slice == "SiteSetting.unicode_usernames" }
raise "unicode route branch source changed" unless unicode_branches.length == 2
unicode_branches.sort_by { |node| -node.location.start_offset }.each do |node|
  url_source[node.location.start_offset - url_node.location.start_offset, node.location.length] = ""
end
url_source = url_source.sub("def construct_url_with(action, opts, url_prefix = nil)", "def construct_latest_json_url_with(action, opts, url_prefix = nil)\n  raise ArgumentError, \"unsupported unicode JSON URL profile\" if SiteSetting.unicode_usernames")
url_source = url_source.sub('public_send(method, opts.merge(page_params))', 'latest_path(format: "json", params: opts.merge(page_params).compact.except(:format))')
record.call(path, url_node, "Preserve real paging/route helper algorithm; enabled unicode URL routing explicitly refuses instead of importing unrelated encoding families")
page_helpers = %i[next_page_params prev_page_params page_params].map do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |method| method.name == name }
  raise "paging helper source changed #{name}" unless node
  code = node.slice.dup
  if name == :page_params
    category = node.body.body.grep(Prism::IfNode).find { |branch| branch.predicate.slice == "@category.present?" }
    raise "category paging source changed" unless category
    code = code.sub(category.slice, '')
    code = code.sub('def page_params', 'def page_params' + "\n raise ArgumentError, \"unsupported categorized latest JSON route\" unless controller_path == \"list\" && action_name == \"latest\"")
  end
  code = code.gsub(/\b(next_page_params|prev_page_params|page_params)\b/) { |token| "latest_json_" + token }
  record.call(path, node, "Actual paging helper; route guard proves set_category callback does not run for list/latest, so original @category is implicitly nil")
  code
end
url_source = url_source.gsub(/\b(next_page_params|prev_page_params)\b/) { |token| "latest_json_" + token }
module_source = <<~RUBY
  # frozen_string_literal: true
  # Fixed original :latest action and actual JSON responder. Not a data backend.
  module PortableLatestJsonAction
    def latest(options = nil)
      return super unless request.format.json?
      latest_json(options)
    end

    def latest_json(options = nil)
      raise ArgumentError, "unsupported non-JSON latest profile" unless request.format.json?
      filter = :latest
      #{json_body}
    end

    #{url_source}

    #{page_helpers.join("\n\n")}

    def respond_with_json_list(list)
      discourse_expires_in 1.minute
      # Fixed TopicList serializer expansion of serialize_data/render_json_dump.
      # All attributes and associations still come from the real serializer.
      payload = TopicListSerializer.new(list, scope: guardian).as_json
      render json: JSON.generate(payload.as_json), status: 200
    end
  end
RUBY

record.call(path, macro, "Expand actual :latest action; fixed dispatch; defer page-only metadata for JSON while retaining original HTML branch")
write.call("lib/portable_latest_json_action.rb", module_source.gsub(/^[ \t]+$/, ""))
controller = source.sub("class ListController < ApplicationController", 'require_relative "../../lib/portable_latest_json_action"' + "\n\nclass ListController < ApplicationController\n  prepend PortableLatestJsonAction")
write.call(path, controller)

# Keep the actual actor class, cache key and nil completion. All credential
# channels outside this explicit profile refuse; none is silently anonymized.
path = "lib/auth/default_current_user_provider.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :current_user }
raise "current-user source changed" unless method&.slice&.include?('@env[CURRENT_USER_KEY] = current_user') && method.slice.include?('current_user = nil')
replacement = <<~RUBY.chomp
  def current_user
    # Supported request profile only. Never accept a credential as anonymous.
    %w[HTTP_COOKIE HTTP_AUTHORIZATION HTTP_X_SHARED_SESSION_KEY HTTP_API_KEY HTTP_API_USERNAME HTTP_API_USER_EXTERNAL_ID HTTP_API_USER_ID HTTP_USER_API_KEY HTTP_USER_API_CLIENT_ID HTTP_DISCOURSE_LOGGED_IN].each do |key|
      value = @env[key]
      raise ArgumentError, "unsupported credential-bearing current-user profile" unless value.nil? || value == ""
    end
    %w[api_key api_username user_api_key user_api_client_id user_api_public_key auth_redirect].each do |key|
      raise ArgumentError, "unsupported credential-bearing current-user query" if @request.params.key?(key)
    end
    unless @env[USER_TOKEN_KEY].nil? && @env[DECRYPTED_AUTH_COOKIE].nil? && @env[CURRENT_USER_KEY].nil? && @env[API_KEY_ENV].nil? && @env[USER_API_KEY_ENV].nil?
      raise ArgumentError, "unsupported preauthenticated current-user context"
    end
    return @env[CURRENT_USER_KEY] if @env.key?(CURRENT_USER_KEY)
    current_user = nil
    @env[CURRENT_USER_KEY] = current_user
  end
RUBY
original_initializer = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :initialize }
record.call(path, original_initializer, "Use actual Rails ActionDispatch::Request subclass instead of Rack::Request for identical no-credential param/env reads")
record.call(path, method, "Real default actor's guarded no-credential completion; every credential/preauthenticated branch explicitly refuses, never a fake user or permission interface")
source[method.location.start_offset, method.location.length] = replacement
initializer = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first.body.body.grep(Prism::DefNode).find { |node| node.name == :initialize }
raise "actor request constructor changed" unless initializer.slice.include?("Rack::Request.new(env)")
# ActionDispatch::Request is the actual Rails subclass of Rack::Request; its
# parsed params/cookies preserve this profile, and it has a native framework API.
source = source.sub("@request = Rack::Request.new(env)", "@request = ActionDispatch::Request.new(env)")
refresh = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :refresh_session }
first_guard = refresh.body.body.first.slice
last_guard = refresh.body.body.last.slice
raise "session refresh boundaries changed" unless first_guard == "return if is_api? || !@env.key?(CURRENT_USER_KEY)" &&
  last_guard == "cookie_jar.delete(TOKEN_COOKIE) if !user && cookie_jar.key?(TOKEN_COOKIE)"
record.call(path, refresh, "Share actual anonymous refresh boundaries and token-cookie deletion; authenticated token rotation explicitly refuses")
source = source.sub(refresh.slice, refresh.slice.sub("def refresh_session(user, session, cookie_jar)\n", "def refresh_session(user, session, cookie_jar)\n    return refresh_session_for_latest_json(user, session, cookie_jar) if @env[PATH_INFO] == \"/latest.json\"\n"))
source += <<~RUBY
  class Auth::DefaultCurrentUserProvider
    def refresh_session_for_latest_json(user, session, cookie_jar)
      #{first_guard}
      raise ArgumentError, "unsupported authenticated session rotation profile" unless user.nil? && @user_token.nil?
      #{last_guard.sub("cookie_jar.key?(TOKEN_COOKIE)", "cookie_jar.to_hash.key?(TOKEN_COOKIE)")}
    end
  end
RUBY
cookie = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :find_v1_auth_cookie }
raise "auth cookie cache source changed" unless cookie&.slice&.include?("env[DECRYPTED_AUTH_COOKIE] = begin")
record.call(path, cookie, "Share actual no-cookie cached nil completion; encrypted/credential-bearing overload profiles explicitly refuse")
source = source.sub(cookie.slice, cookie.slice.sub("def self.find_v1_auth_cookie(env)\n", "def self.find_v1_auth_cookie(env)\n    return find_v1_auth_cookie_for_latest_json(env) if env[\"PATH_INFO\"] == \"/latest.json\"\n"))
source += <<~RUBY
  class Auth::DefaultCurrentUserProvider
    def self.find_v1_auth_cookie_for_latest_json(env)
      header = env["HTTP_COOKIE"]
      raise ArgumentError, "unsupported credential-bearing overload cookie profile" unless header.nil? || header == ""
      raise ArgumentError, "unsupported preauthenticated overload cookie profile" unless env[DECRYPTED_AUTH_COOKIE].nil?
      return env[DECRYPTED_AUTH_COOKIE] if env.key?(DECRYPTED_AUTH_COOKIE)
      env[DECRYPTED_AUTH_COOKIE] = nil
    end
  end
RUBY
write.call(path, source)

path = "lib/middleware/overload_protections.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ClassNode).first
call = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :call }
response = call.body.body.first.statements.body.first.slice
raise "original overload response changed" unless response.start_with?("return [") && response.include?("503") && response.include?("Server is currently experiencing high load.")
record.call(path, call, "Execute original overload predicate/503 response before profiler; source queue parser and live threshold retained, unimplemented authentication explicitly refuses")
source = source.sub(call.slice, call.slice.sub("def call(env)\n", "def call(env)\n      return call_latest_json(env) if env[\"REQUEST_METHOD\"] == \"GET\" && env[\"PATH_INFO\"] == \"/latest.json\"\n"))
source += <<~RUBY
  module Middleware
    class OverloadProtections
      def call_latest_json(env)
        unless env["REQUEST_METHOD"] == "GET" && env["PATH_INFO"] == "/latest.json"
          raise ArgumentError, "unsupported overload request method/path profile"
        end
        if overloaded_for_latest_json?(env) && !authenticated_request_for_latest_json?(env)
          #{response}
        end
        @app.call(env)
      end

      def overloaded_for_latest_json?(env)
        env[Middleware::ProcessingRequest::REQUEST_QUEUE_SECONDS_ENV_KEY].to_f >
          SiteSetting.portable_reject_anonymous_min_queue_seconds
      end

      def authenticated_request_for_latest_json?(env)
        cookie = Auth::DefaultCurrentUserProvider.find_v1_auth_cookie_for_latest_json(env)
        raise ArgumentError, "unsupported authenticated overload cookie profile" unless cookie.nil?
        if api_credentials_present?(env)
          raise ArgumentError, "unsupported credential-bearing overload API profile"
        end
        false
      end
    end
  end
RUBY
write.call(path, source)

path = "lib/json_error.rb"
error_source = read.call(path)
error_owner = Prism.parse(error_source).value.statements.body.grep(Prism::ModuleNode).first
error_method = error_owner.body.body.grep(Prism::DefNode).find { |node| node.name == :create_errors_array }
string_branch = error_method.body.body.grep(Prism::IfNode).find { |node| node.predicate.slice == 'obj.is_a?(String)' }
raise "source String JSON error branch changed" unless string_branch
replacement = "def create_errors_array(obj)\n #{string_branch.slice}\n raise ArgumentError, \"unsupported non-String JSON error profile\"\nend"
record.call(path, error_method, "Retain actual String-message error representation; non-String actor/record/error families explicitly refuse")
error_source[error_method.location.start_offset, error_method.location.length] = replacement
write.call(path, error_source)

path = "app/controllers/application_controller.rb"
application_source = read.call(path)
application_owner = Prism.parse(application_source).value.statements.body.grep(Prism::ClassNode).first
application_owner.body.body.grep(Prism::DefNode).each do |node|
  if node.name == :guardian
    raise "guardian identity refresh source changed" unless node.slice.include?('@guardian&.user.blank? && current_user.present?')
    record.call(path, node, "Explicit nil checks preserve actual User-or-nil guardian refresh without relying on Object#blank? core extensions")
    application_source = application_source.sub('@guardian&.user.blank? && current_user.present?', '(@guardian.nil? || @guardian.user.nil?) && !current_user.nil?')
  elsif node.name == :dont_cache_page
    record.call(path, node, "Response cache_control is always a nonnil Hash/store; empty? preserves blank? without dynamic Object reflection")
    application_source = application_source.sub('response.cache_control.blank?', 'response.cache_control.empty?')
  elsif node.name == :preload_json
    record.call(path, node, "Explicit format nil check preserves safe-navigation semantics and permits ordinary shared MIME lowering")
    application_source = application_source.sub('request.format&.json?', '(request.format && request.format.json?)')
  elsif node.name == :param_to_integer_list
    record.call(path, node, "String key access is equivalent for real Rails Parameters and framework parsed params")
    application_source = application_source.sub(node.slice, node.slice.sub('params[key]', 'params[key.to_s]'))
  end
end
# Keep parameter-error rescue OUTSIDE process_action callbacks, as in Rails.
# The old action-local rescue returned normally through after filters and
# rendered before locale unwound; readonly+400/locale controls expose that bug.
parameter_rescue = application_owner.body.body.grep(Prism::CallNode).find do |node|
  node.name == :rescue_from && node.arguments&.arguments&.first&.slice == "Discourse::InvalidParameters"
end
raise "original parameter rescue changed" unless parameter_rescue&.block&.parameters&.slice == "|e|"
record.call(path, parameter_rescue, "Share actual JSON parameter error formatting at original outer rescue_from boundary; retain original other-format handler")
handler = <<~RUBY.chomp
  rescue_from Discourse::InvalidParameters do |e|
    if request.format && request.format.json?
      render_latest_json_parameter_error(e)
    else
      #{parameter_rescue.block.body.slice}
    end
  end
RUBY
application_source = application_source.sub(parameter_rescue.slice, handler)
application_source += <<~RUBY
  class ApplicationController
    def render_latest_json_parameter_error(error)
      # Original rescue_discourse_actions translates inside a SECOND resolved
      # locale scope after the failed action's scope has already unwound.
      message = ""
      with_resolved_locale_for_latest_json do
        message = I18n.t("invalid_params", message: error.message)
      end
      render json: JSON.generate(create_errors_json(message, type: :invalid_parameters)), status: 400
    end
  end
RUBY

# Split only the anonymous JSON logging branches into shared components.
# The real non-JSON/authenticated implementations remain in the full candidate;
# credentials are already refused by the actor profile, never anonymized.
%w[set_current_user_for_logs set_current_user_header_for_logs].each do |name|
  node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name.to_s == name }
  raise "logging callback source changed #{name}" unless node
  component = name.sub("_for_logs", "_for_latest_json_logs")
  header = name == "set_current_user_for_logs" ? 'response.headers["X-Discourse-Route"] = "#{controller_path}/#{action_name}"' : "nil"
  raise "route logging source changed" if name == "set_current_user_for_logs" && !node.slice.include?(header)
  record.call(path, node, "Separate actual anonymous JSON logging completion, guarded by real current_user.nil?; retain original other profiles")
  replacement = node.slice.sub("def #{name}\n", "def #{name}\n    return #{component} if request.format.json?\n")
  application_source = application_source.sub(node.slice, replacement)
  application_source += "\nclass ApplicationController\n  def #{component}\n    raise ArgumentError, \"unsupported authenticated JSON logging profile\" unless current_user.nil?\n    #{header}\n  end\nend\n"
end
# Named-controller policy registry preserves the original per-class (NOT
# inherited) requires_login DSL and its live arguments. No observed nil policy
# is baked in. Moving the state out of controller class ivars avoids the
# measured controller-side class-ivar typing gap without weakening the guard.
%w[requires_login requires_login_arg].each do |name|
  node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name.to_s == name }
  record.call(path, node, "Store original writable per-named-controller login policy in shared portable registry")
  replacement = if name == "requires_login"
    "def self.requires_login(arg = {})\n PortableControllerLoginPolicy.set(name, arg)\nend"
  else
    "def self.requires_login_arg\n PortableControllerLoginPolicy.get(name)\nend"
  end
  application_source = application_source.sub(node.slice, replacement)
end
application_source = application_source.sub('require "current_user"', 'require "current_user"' + "\nrequire_relative \"../../lib/portable_controller_login_policy\"")
write.call("lib/portable_controller_login_policy.rb", <<~RUBY)
  # frozen_string_literal: true
  # Shared live requires_login DSL storage. Arguments belong to the named
  # class itself, not its parent, exactly as the original class-instance ivar.
  class PortableControllerLoginPolicy
    @arguments = {}
    def self.set(name, argument)
      raise ArgumentError, "unsupported anonymous controller login policy" if name.nil? || name.empty?
      @arguments[name] = argument
    end
    def self.get(name)
      raise ArgumentError, "unsupported anonymous controller login policy" if name.nil? || name.empty?
      @arguments[name]
    end
  end
RUBY

node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :set_mp_snapshot_fields }
raise "snapshot fields source changed" unless node.slice.include?('Rack::MiniProfiler.add_snapshot_custom_field("Application version", Discourse.git_version)')
record.call(path, node, "Share real profiler snapshot fields with child-free live GitUtils filesystem version reader; transporter profiles explicitly refuse")
application_source = application_source.sub(node.slice, node.slice.sub("def set_mp_snapshot_fields\n", "def set_mp_snapshot_fields\n    return set_mp_snapshot_fields_for_latest_json if request.format.json?\n"))
application_source += <<~RUBY
  class ApplicationController
    def set_mp_snapshot_fields_for_latest_json
      Rack::MiniProfiler.add_snapshot_custom_field("Application version", PortableGitVersion.read(PortableGitVersion.application_root))
      raise ArgumentError, "unsupported snapshot transporter JSON profile" if Rack::MiniProfiler.snapshots_transporter?
    end
  end
RUBY
application_source = application_source.sub('require "current_user"', 'require "current_user"' + "\nrequire_relative \"../../lib/portable_git_version\"")
read.call("lib/git_utils.rb")

node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :with_resolved_locale }
raise "locale callback source changed" unless node.slice.include?("Discourse.anonymous_locale(request)") && node.slice.include?("I18n.with_locale(locale) { yield }")
record.call(path, node, "Execute real default-anonymous locale scope; selected locale overrides/non-default source locale explicitly refuse, actual values never forced off")
application_source = application_source.sub(node.slice, node.slice.sub("def with_resolved_locale(check_current_user: true)\n", "def with_resolved_locale(check_current_user: true)\n    if request.format.json?\n      return with_resolved_locale_for_latest_json { yield }\n    end\n"))
application_source += <<~RUBY
  class ApplicationController
    def with_resolved_locale_for_latest_json
      raise ArgumentError, "unsupported authenticated JSON locale profile" unless current_user.nil?
      cookie_header = request.env["HTTP_COOKIE"]
      raise ArgumentError, "unsupported cookie-selected JSON locale profile" unless cookie_header.nil? || cookie_header.empty?
      locale_input = params["tl"] if SiteSetting.set_locale_from_param
      locale_input ||= request.env["HTTP_ACCEPT_LANGUAGE"] if SiteSetting.set_locale_from_accept_language_header
      raise ArgumentError, "unsupported selected JSON locale override profile" unless locale_input.nil? || locale_input == ""
      # HttpLanguageParser.parse(nil/empty) falls through to this LIVE source
      # default. The original persistence predicate is false with no tl input.
      locale = SiteSetting.default_locale
      unless locale == SiteSettings::DefaultsProvider::DEFAULT_LOCALE
        raise ArgumentError, "unsupported non-default JSON application locale profile"
      end
      SiteSetting.portable_prepare_request_locale(locale)
      I18n.with_locale(locale) { yield }
    end
  end
RUBY
%w[lib/http_language_parser.rb lib/freedom_patches/translate_accelerator.rb config/locales/server.fr.yml config/locales/client.fr.yml].each { |name| read.call(name) }

# Keep real theme resolution, safe-mode predicates and preloader allocation
# on JSON requests. Only authenticated/preview/cookie-specific branches refuse;
# the default theme still comes from live settings and actual DB permissions.
node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :initialize_application_layout_preloader }
record.call(path, node, "Share real preloader allocation; call original MobileDetection directly instead of allocating a page view context for JSON")
application_source = application_source.sub(node.slice, node.slice.sub("def initialize_application_layout_preloader\n", "def initialize_application_layout_preloader\n    return initialize_application_layout_preloader_for_latest_json if request.format.json?\n"))
component = node.slice.sub("def initialize_application_layout_preloader", "def initialize_application_layout_preloader_for_latest_json")
component = component.sub("view_context.mobile_device?", "MobileDetection.mobile_device?(request.user_agent)").sub("login_method:", "login_method: login_method_for_latest_json")
application_source += "\nclass ApplicationController\n#{component}\nend\n"
login = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :login_method }
record.call(path, login, "Actual no-user login-method return; authenticated OAuth/local branch explicitly refuses for JSON")
application_source += <<~RUBY
  class ApplicationController
    def login_method_for_latest_json
      return if !current_user
      raise ArgumentError, "unsupported authenticated JSON layout login method"
    end
  end
RUBY
application_source = application_source.sub('require "current_user"', 'require "current_user"' + "\nrequire_relative \"../../lib/mobile_detection\"")

# These are real early-return branches, not empty callback stand-ins. The
# shared JSON component retains the source predicate; branches whose effects
# are not yet supported fail closed. Full candidate non-JSON code is retained.
node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :redirect_to_profile_if_required }
guard = node.body.body.first
raise "profile JSON early return changed" unless guard.slice == "return if request.format.json?"
component = "redirect_to_profile_for_latest_json"
record.call(path, node, "Share actual JSON early return; authenticated/HTML profile redirects remain in original method")
application_source = application_source.sub(node.slice, node.slice.sub("def redirect_to_profile_if_required\n", "def redirect_to_profile_if_required\n    return #{component} if request.format.json?\n"))
application_source += "\nclass ApplicationController\n def #{component}\n #{guard.slice}\n raise ArgumentError, \"unsupported non-JSON profile redirect\"\n end\nend\n"

node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :clear_notifications }
predicate = node.body.body.first.predicate.slice
raise "notification guard changed" unless predicate == "current_user && !@readonly_mode"
record.call(path, node, "Retain actual actor/readonly predicate in shared anonymous JSON branch; notification mutations explicitly unsupported")
application_source = application_source.sub(node.slice, node.slice.sub("def clear_notifications\n", "def clear_notifications\n    return clear_notifications_for_latest_json if request.format.json?\n"))
application_source += <<~RUBY
  class ApplicationController
    def clear_notifications_for_latest_json
      if #{predicate}
        raise ArgumentError, "unsupported authenticated notification mutation profile"
      end
    end
  end
RUBY

node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :mini_profiler_enabled? }
guards = node.body.body.first(2).map(&:slice)
raise "profiler development guard changed" unless guards == ["return false unless MINI_PROFILER_CLASS", "return true if Rails.env.development?"]
record.call(path, node, "Share actual available/development profiler predicates; encrypted-cookie authorization outside this profile refuses")
application_source = application_source.sub(node.slice, node.slice.sub("def mini_profiler_enabled?\n", "def mini_profiler_enabled?\n    return mini_profiler_enabled_for_latest_json? if request.format.json?\n"))
application_source += "\nclass ApplicationController\n def mini_profiler_enabled_for_latest_json?\n #{guards.join("\n")}\n raise ArgumentError, \"unsupported non-development profiler authorization\"\n end\nend\n"
node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :redirect_to_login_if_required }
branches = node.body.body
api_guard = branches[0].slice
key_guard = branches[1].predicate.slice
login_guard = branches[2].predicate.slice
anonymous_guard = branches[3].slice
raise "login JSON source predicates changed" unless api_guard == "return if request.format.json? && is_api?" &&
  key_guard == "!current_user && params.has_key?(:user_api_public_key) && params.has_key?(:auth_redirect)" &&
  login_guard == "!current_user && SiteSetting.login_required?" && anonymous_guard == "return if !current_user"
record.call(path, node, "Share actual API/user/login-required guards; unsupported OAuth/2FA profiles explicitly refuse instead of anonymizing")
application_source = application_source.sub(node.slice, node.slice.sub("def redirect_to_login_if_required\n", "def redirect_to_login_if_required\n    return redirect_to_login_for_latest_json if request.format.json?\n"))
application_source += <<~RUBY
  class ApplicationController
    def redirect_to_login_for_latest_json
      #{api_guard}
      if #{key_guard}
        raise ArgumentError, "unsupported user-API authentication redirect profile"
      end
      if #{login_guard}
        raise ArgumentError, "unsupported login-required JSON request profile"
      end
      #{anonymous_guard}
      raise ArgumentError, "unsupported authenticated two-factor redirect profile"
    end
  end
RUBY
# Object#blank? on this real provider's User-or-nil contract is a nil check.
node = application_owner.body.body.grep(Prism::DefNode).find { |method| method.name == :ensure_logged_in }
raise "ensure logged in source changed" unless node.slice.include?("current_user.blank?")
record.call(path, node, "Equivalent nil predicate on actual User-or-nil actor contract; preserve original NotLoggedIn error")
application_source = application_source.sub(node.slice, node.slice.sub("current_user.blank?", "current_user.nil?"))
write.call(path, application_source)

# Preserve the actual GET/HEAD guards before mutating readonly/archive policy.
# Native only imports this JSON component, while candidate Rails still retains
# the complete policy for non-JSON requests.
%w[read_only_mixin archived_site_mixin].each do |basename|
  path = "lib/#{basename}.rb"
  source = read.call(path)
  owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
  name = basename == "read_only_mixin" ? :block_if_readonly_mode : :block_if_archived
  node = owner.body.body.grep(Prism::DefNode).find { |method| method.name == name }
  guard = node.body.body.first
  raise "readonly GET/HEAD guard changed" unless guard.slice == "return if request.get? || request.head?"
  component = "#{name}_for_latest_json"
  record.call(path, node, "Share actual GET/HEAD early return; mutating JSON policy remains explicitly unsupported")
  replacement = node.slice.sub("def #{name}\n", "def #{name}\n    return #{component} if request.format.json?\n")
  source = source.sub(node.slice, replacement)
  if basename == "read_only_mixin"
    checker = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :check_readonly_mode }
    record.call(path, checker, "Same actual readonly/staff state transitions with live shared Redis/force/error-time reader; no frozen mode or fake cache")
    source = source.sub(checker.slice, checker.slice.sub("def check_readonly_mode\n", "def check_readonly_mode\n    return check_readonly_mode_for_latest_json(Discourse.redis, GlobalSetting.pg_force_readonly_mode, Discourse.redis_last_read_only[Discourse.redis.namespace]) if request.format.json?\n"))
    component_source = checker.slice.sub("def check_readonly_mode", "def check_readonly_mode_for_latest_json(redis, force, redis_error_at)")
      .sub("Discourse.readonly_mode?", "PortableReadonlyState.readonly?(redis, force, redis_error_at, Time.now)")
      .sub("Discourse.staff_writes_only_mode?", "PortableReadonlyState.staff_writes_only?(redis)")
    source += "\nmodule ReadOnlyMixin\n#{component_source}\nend\n"
    source = 'require_relative "portable_readonly_declarations"' + "\n" + source
  end
  source += "\nmodule #{owner.constant_path.slice}\n def #{component}\n #{guard.slice}\n raise ArgumentError, \"unsupported mutating JSON request profile\"\n end\nend\n"
  write.call(path, source)
end

discourse_source = read.call("lib/discourse.rb")
discourse_owner = Prism.parse(discourse_source).value.statements.body.grep(Prism::ModuleNode).first
readonly_names = %i[LAST_POSTGRES_READONLY_KEY READONLY_MODE_KEY PG_READONLY_MODE_KEY USER_READONLY_MODE_KEY PG_FORCE_READONLY_MODE_KEY STAFF_WRITES_ONLY_MODE_KEY READONLY_KEYS]
readonly_constants = discourse_owner.body.body.grep(Prism::ConstantWriteNode).select { |node| readonly_names.include?(node.name) }
raise "readonly source constants changed" unless readonly_constants.length == readonly_names.length
readonly_constants.each { |node| record.call("lib/discourse.rb", node, "Actual pinned readonly key declarations, never an observed mode") }
write.call("lib/portable_readonly_declarations.rb", 'require_relative "portable_readonly_state"' + "\nclass PortableReadonlyState\n" + readonly_constants.map(&:slice).join("\n") + "\nend\n")

path = "lib/markdown_endpoint/controller_support.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first.body.body.grep(Prism::ModuleNode).first
%w[normalize_markdown_format add_markdown_discovery_header].each do |name|
  node = owner.body.body.grep(Prism::DefNode).find { |method| method.name.to_s == name }
  count = name == "normalize_markdown_format" ? 1 : 2
  guards = node.body.body.first(count).map(&:slice)
  expected = name == "normalize_markdown_format" ? ["return unless request.format.md?"] :
    ["return unless response.status.between?(200, 299)", 'return unless response.media_type == "text/html"']
  raise "Markdown early-return guards changed" unless guards == expected
  component = "#{name}_for_latest_json"
  record.call(path, node, "Shared actual Markdown guards; non-JSON response/negotiation effects explicitly refuse in this component")
  source = source.sub(node.slice, node.slice.sub("def #{name}\n", "def #{name}\n      return #{component} if request.format.json?\n"))
  # Response.media_type strips content-type parameters on real Rails. This
  # explicit equivalent is shared with the framework's response abstraction.
  guards = guards.map { |text| text.sub("response.media_type", 'response.content_type.to_s.split(";", 2).first') }
  source += "\nmodule MarkdownEndpoint\n module ControllerSupport\n def #{component}\n #{guards.join("\n")}\n raise ArgumentError, \"unsupported non-JSON Markdown callback profile\"\n end\n end\nend\n"
end
write.call(path, source)
read.call("config/initializers/markdown_endpoints.rb")

path = "lib/theme_resolver.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
node = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :resolve_theme_id }
raise "theme resolution source changed" unless node.slice.include?("guardian.allow_themes?([SiteSetting.default_theme_id])") && node.slice.include?("user_option&.theme_ids || []")
record.call(path, node, "Share anonymous default-theme algorithm with live permissions; preview/cookie/user themes explicitly refuse; private env memoization uses a String key")
source = source.sub(node.slice, node.slice.sub("def self.resolve_theme_id(request, guardian, current_user)\n", "def self.resolve_theme_id(request, guardian, current_user)\n    return resolve_latest_json_theme_id(request, guardian, current_user) if request.params[\"format\"].to_s == \"json\"\n"))
source += <<~RUBY
  module ThemeResolver
    def self.resolve_latest_json_theme_id(request, guardian, current_user)
      raise ArgumentError, "unsupported authenticated JSON theme profile" unless current_user.nil?
      cached = request.env["discourse.resolved_theme_id"]
      return cached unless cached.nil?
      raise ArgumentError, "unsupported preview JSON theme profile" if request.params.key?("preview_theme_id")
      cookie_header = request.env["HTTP_COOKIE"]
      raise ArgumentError, "unsupported cookie-selected JSON theme profile" unless cookie_header.nil? || cookie_header.empty?
      theme_id = nil
      # Original user_option&.theme_ids || [] under the verified nil user.
      ids = []
      theme_id = ids.first if guardian.allow_themes?(ids)
      if theme_id.blank? && guardian.allow_themes?([SiteSetting.default_theme_id])
        theme_id = SiteSetting.default_theme_id
      end
      request.env["discourse.resolved_theme_id"] = theme_id
    end
  end
RUBY
write.call(path, source)
read.call("lib/mobile_detection.rb")
read.call("lib/application_layout_preloader.rb")
read.call("app/helpers/application_helper.rb")

path = "lib/crawler_detection.rb"
source = read.call(path)
owner = Prism.parse(source).value.statements.body.grep(Prism::ModuleNode).first
node = owner.body.body.grep(Prism::DefNode).find { |method| method.name == :crawler_layout_request? }
guards = node.body.body.first(4).map(&:slice)
raise "crawler format guard changed" unless guards.last == 'return false if %w[json rss].include?(request.params[:format].to_s)'
record.call(path, node, "Shared genuine nil/agent/media/format guards; HTML crawler determination stays in original method")
source = source.sub(node.slice, node.slice.sub("def self.crawler_layout_request?(request)\n", "def self.crawler_layout_request?(request)\n    return crawler_layout_request_for_latest_json?(request) if request && request.params[\"format\"].to_s == \"json\"\n"))
# The original Rack media_type is the CONTENT_TYPE stripped of parameters.
# No User-Agent or media type is forced off to select the JSON early return.
guards[0] = guards[0].sub("request.blank?", "request.nil?")
guards[1] = guards[1].sub("request.user_agent.blank?", "(request.user_agent.nil? || request.user_agent.empty?)")
guards[2] = 'return false if !media_type.empty? && !media_type.include?("html")'
guards[3] = guards[3].sub('request.params[:format]', 'request.params["format"]')
source += <<~RUBY
  module CrawlerDetection
    def self.crawler_layout_request_for_latest_json?(request)
      #{guards.first(2).join("\n")}
      media_type = request.env["CONTENT_TYPE"].to_s.split(";", 2).first.to_s.strip.downcase
      #{guards.last(2).join("\n")}
      raise ArgumentError, "unsupported non-JSON crawler callback profile"
    end
  end
RUBY
write.call(path, source)

path = "lib/topic_query_params.rb"
params_source = read.call(path)
params_owner = Prism.parse(params_source).value.statements.body.grep(Prism::ModuleNode).first
params_method = params_owner.body.body.grep(Prism::DefNode).find { |node| node.name == :build_topic_list_options }
record.call(path, params_method, "String keys work identically in Rails Parameters and framework parsed Hashes; no request option or validator is dropped")
params_source = params_source.sub('params.key?(key)', 'params.key?(key.to_s)').sub('val = params[key]', 'val = params[key.to_s]')
write.call(path, params_source)

%w[config/application.rb app/controllers/application_controller.rb lib/auth.rb lib/current_user.rb lib/topic_list_responder.rb lib/read_only_mixin.rb lib/vary_header.rb lib/crawler_detection.rb].each { |name| read.call(name) }
File.write(lock_path, JSON.pretty_generate(lock) + "\n")
directory = File.join(root, "fidelity/progressive/stage4_request")
FileUtils.mkdir_p(directory)
manifest = {profile: "WIP shared latest controller action and guarded real actor; NOT native request acceptance",
  baseline_revision: pin, source_sha256: inputs, candidate_source_sha256: outputs,
  guarded_changes: changes, effective_values_or_observed_payloads_used: false,
  json_request_accepted: false, full_query_accepted: false, page_accepted: false}
File.write(File.join(directory, "MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate({profile: manifest[:profile], outputs: outputs.keys})

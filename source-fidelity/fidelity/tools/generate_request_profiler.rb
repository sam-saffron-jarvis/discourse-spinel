# frozen_string_literal: true
# Build-time original gem READ components for the genuine core request path.
# No observed profiler values/IDs/SQL/payloads are inputs. Unchanged originals
# remain separately hashed; unsupported implicit connections refuse explicitly.
require "prism"
require "json"
require "digest"
require "fileutils"

root = File.expand_path("../..", __dir__)
gem_root = File.join(root, "run/bundle/ruby/4.0.0/gems")
original = File.join(root, "fidelity/source/framework")
parts = []
hashes = {}
read = lambda do |name|
  bytes = File.binread(File.join(gem_root, name))
  target = File.join(original, name)
  raise "immutable profiler reference changed #{name}" if File.exist?(target) && File.binread(target) != bytes
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, bytes) unless File.exist?(target)
  hashes[name] = Digest::SHA256.hexdigest(bytes)
  bytes
end
walk = lambda do |node, &predicate|
  return node if predicate.call(node)
  node.compact_child_nodes.each do |child|
    found = walk.call(child, &predicate)
    return found if found
  end
  nil
end
extract = lambda do |path, owner_name, methods|
  bytes = read.call(path)
  owner = walk.call(Prism.parse(bytes).value) { |node| (node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode)) && node.constant_path.slice == owner_name }
  raise "missing profiler owner #{owner_name}" unless owner
  methods.map do |name|
    node = walk.call(owner) { |item| item.is_a?(Prism::DefNode) && item.name == name }
    raise "missing profiler method #{owner_name}:#{name}" unless node
    parts << {source: path, start_byte: node.location.start_offset, end_byte: node.location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(node.slice)}
    node.slice
  end.join("\n\n")
end
prefix = "rack-mini-profiler-5.0.0/lib/mini_profiler/"
text = "# frozen_string_literal: true\n# GENERATED original profiler5 core components; not full debug/HTML/profile API acceptance.\nrequire \"json\"\nrequire \"digest\"\nrequire \"cgi\"\nrequire \"securerandom\"\nmodule Rack\nclass MiniProfiler\n"
# Same base-36 distribution as rand(36**20).to_s(36), without requiring a
# 104-bit random bound. This is the existing framework port, not an observed ID.
text += <<~RUBY
  def self.generate_id
    alphabet = "0123456789abcdefghijklmnopqrstuvwxyz"
    out = +""
    i = 0
    while i < 20
      digit = rand(36)
      out << alphabet[digit] unless out.empty? && digit == 0
      i += 1
    end
    out.empty? ? "0" : out
  end
RUBY
read.call("rack-mini-profiler-5.0.0/lib/mini_profiler.rb")
text += "module TimerStruct\n"
{
  "Base" => %i[initialize attributes [] []= to_json],
  "Page" => %i[initialize page_name root duration_ms attributes_to_serialize to_json extra_json],
  "Request" => %i[createRoot initialize depth record_time duration_ms add_child add_sql add_custom],
  "Sql" => %i[initialize trim_binds report_reader_duration],
  "Custom" => %i[initialize],
}.each do |name, methods|
  path = prefix + "timer_struct/" + name.downcase + ".rb"
  body = extract.call(path, name, methods)
  # ERB::Util.html_escape is CGI.escapeHTML; use its actual stdlib primitive
  # without importing an unrelated ERB compiler for a profiler SQL label.
  body = body.gsub("ERB::Util.html_escape(query)", "CGI.escapeHTML(query)") if name == "Sql"
  attrs = case name
  when "Request" then "attr_accessor :children_duration, :start, :parent"
  when "Sql", "Custom" then "attr_accessor :parent"
  else ""
  end
  text += "class #{name}#{name == 'Base' ? '' : ' < Base'}\n#{attrs}\n#{body}\nend\n"
end
text += "end\n"

# Keep actual Context fields and empty-options semantics, replacing dynamic
# instance_variable_set with explicit assignments. Nonempty options refuse.
read.call(prefix + "context.rb")
text += <<~RUBY
  class Context
    attr_accessor :inject_js, :current_timer, :page_struct, :skip_backtrace,
      :full_backtrace, :discard, :mpt_init, :measure
    def initialize(opts = {})
      raise ArgumentError, "unsupported profiler context options" unless opts.empty?
      @inject_js = nil
      @current_timer = nil
      @page_struct = nil
      @skip_backtrace = nil
      @full_backtrace = nil
      @discard = nil
      @mpt_init = nil
      @measure = true
    end
  end
RUBY

# Static expansion of real Config.default assignments for the methods above.
# The original per-application initializer still supplies live configuration.
config_source = read.call(prefix + "config.rb")
default = walk.call(Prism.parse(config_source).value) { |node| node.is_a?(Prism::DefNode) && node.name == :default }
fields = %i[auto_inject cookie_path disable_caching enabled authorization_mode max_traces_to_show
  max_sql_param_length backtrace_threshold_ms backtrace_remove backtrace_includes backtrace_ignores
  snapshots_transport_destination_url snapshots_transport_auth_key profile_parameter storage_instance
  base_url_path storage_failure logger pre_authorize_cb user_provider skip_paths suppress_encoding
  snapshot_every_n_requests position snapshots_redact_sql_queries]
assignments = fields.map do |field|
  node = walk.call(default) { |item| item.is_a?(Prism::InstanceVariableWriteNode) && item.name.to_s == "@#{field}" }
  if node
    parts << {source: prefix + "config.rb", start_byte: node.location.start_offset, end_byte: node.location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(node.slice)}
    node.slice
  else
    "@#{field} = nil"
  end
end
text += "class Config\nattr_accessor #{fields.map { |name| ':' + name.to_s }.join(', ')}\ndef initialize\n#{assignments.join("\n")}\nend\ndef self.default\nnew\nend\nend\n"
main_methods = %i[config current current= create_current authorize_request deauthorize_request request_authorized?
  add_snapshot_custom_field get_snapshot_custom_fields snapshots_transporter? redact_sql_queries?]
main = extract.call("rack-mini-profiler-5.0.0/lib/mini_profiler.rb", "MiniProfiler", main_methods)
# Spell the fixed original TLS key literally and initialize with the ACTUAL
# first field, not an untyped empty Hash shared with unrelated TLS shapes.
# Same hash identity/update/return semantics; no test values or omitted fields.
snapshot = walk.call(Prism.parse("class Probe\n#{main}\nend").value) { |node| node.is_a?(Prism::DefNode) && node.name == :add_snapshot_custom_field }
raise "original snapshot field storage changed" unless snapshot&.slice&.include?("Thread.current[thread_var_key][key] = value")
main = main.sub(snapshot.slice, <<~RUBY.chomp)
  def add_snapshot_custom_field(key, value)
    fields = Thread.current[:mini_profiler_snapshot_custom_fields]
    if fields
      fields[key] = value
    else
      Thread.current[:mini_profiler_snapshot_custom_fields] = {key => value}
    end
    value
  end
RUBY
# Original methods are under class << self; make that lexical owner explicit.
text += "class << self\n#{main}\n" + extract.call(prefix + "profiling_methods.rb", "ProfilingMethods", %i[record_sql start_step finish_step]) + "\nend\n"
# Original instance helpers, not same-named class-side configuration readers.
main_source = read.call("rack-mini-profiler-5.0.0/lib/mini_profiler.rb")
main_owner = walk.call(Prism.parse(main_source).value) { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "MiniProfiler" }
%i[current current= config user ids ids_comma_separated flamegraph_path inject_profiler].each do |name|
  node = main_owner.body.body.grep(Prism::DefNode).find { |item| item.name == name }
  raise "missing original profiler instance helper #{name}" unless node
  parts << {source: "rack-mini-profiler-5.0.0/lib/mini_profiler.rb", start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice)}
  code = node.slice
  if name == :inject_profiler
    branch = walk.call(node) { |item| item.is_a?(Prism::IfNode) && item.predicate.slice.include?("current.inject_js && content_type") }
    raise "original HTML profiler injection branch changed" unless branch
    code = code.sub(branch.slice, 'raise ArgumentError, "unsupported profiler HTML injection profile" if current.inject_js && content_type =~ /text\\/html/; nil')
  end
  text += code + "\n"
end
abstract = read.call(prefix + "storage/abstract_store.rb")
age = walk.call(Prism.parse(abstract).value) { |node| node.is_a?(Prism::ConstantWriteNode) && node.name == :MAX_TOKEN_AGE }
raise "original token age missing" unless age
text += "class AbstractStore\n#{age.slice}\nend\n"

store_methods = %i[initialize save load set_unviewed get_unviewed_ids set_all_unviewed allowed_tokens prefixed_id user_key]
store = extract.call(prefix + "storage/redis_store.rb", "RedisStore", store_methods)
text += "class RedisStore\nEXPIRES_IN_SECONDS = 60 * 60 * 24\n#{store}\ndef redis\nraise ArgumentError, \"profiler requires an explicitly injected Redis connection\" if @redis_connection.nil?\n@redis_connection\nend\nend\n"
text += "end\nend\n"

# Pinned Rack2 header names and cookie encoder, not a sampled profiler cookie.
rack = read.call("rack-2.2.24/lib/rack.rb")
constants = %i[CONTENT_TYPE CACHE_CONTROL ETAG SET_COOKIE].map do |name|
  node = walk.call(Prism.parse(rack).value) { |item| item.is_a?(Prism::ConstantWriteNode) && item.name == name }
  raise "missing pinned Rack header #{name}" unless node
  parts << {source: "rack-2.2.24/lib/rack.rb", start_byte: node.location.start_offset, end_byte: node.location.end_offset,
    text_sha256: Digest::SHA256.hexdigest(node.slice)}
  node.slice
end
cookie_methods = extract.call("rack-2.2.24/lib/rack/utils.rb", "Utils", %i[escape add_cookie_to_header set_cookie_header!])
cookie_methods = cookie_methods.sub("URI.encode_www_form_component(s)", "CGI.escape(s.to_s)")
text += "module Rack\n#{constants.join("\n")}\nmodule Utils\nclass << self\n#{cookie_methods}\n"
text += "def delete_cookie_header!(headers, key, value = {})\nraise ArgumentError, \"unsupported existing profiler cookie deletion\"\nend\nend\nend\nend\n"
client = read.call(prefix + "client_settings.rb")
client = client.sub("::Rack::Request.new(env)", "::Rack::CoreRequest.new(env)")
text += client
text = text.sub("# frozen_string_literal: true\n", "# frozen_string_literal: true\nrequire_relative \"portable_profiler_request\"\n")

raise "invalid original profiler component" unless Prism.parse(text).success?
path = File.join(root, "fidelity/compat/framework/rack_mini_profiler_core.rb")
FileUtils.mkdir_p(File.dirname(path))
File.binwrite(path, text)
initializer_path = File.join(root, "discourse/config/initializers/006-mini_profiler.rb")
initializer_source = File.binread(initializer_path)
skip = walk.call(Prism.parse(initializer_source).value) { |node| node.is_a?(Prism::CallNode) && node.name == :skip_paths= && node.receiver&.slice == "Rack::MiniProfiler.config" }
raise "original profiler skip-path declaration changed" unless skip
skip_value = skip.arguments.arguments.first.slice.gsub("Discourse.base_path", "base_path")
declarations = "# frozen_string_literal: true\n# GENERATED actual application profiler path declarations, not observed values.\nmodule PortableProfilerDeclarations\ndef self.skip_paths(base_path)\n#{skip_value}\nend\nend\n"
File.binwrite(File.join(root, "fidelity/compat/framework/portable_profiler_declarations.rb"), declarations)
processing_path = "lib/middleware/processing_request.rb"
processing_source = File.binread(File.join(root, "discourse", processing_path))
File.binwrite(File.join(root, "fidelity/compat/framework/portable_request_processing.rb"), "# frozen_string_literal: true\nmodule Middleware\nend\n" + processing_source)
require_relative "generate_response_middleware"
require_relative "generate_json_profile_middleware"
json_profile_middleware = generate_json_profile_middleware(root, read, parts)
require_relative "generate_remote_ip"
remote_ip = generate_remote_ip(root, read, parts)
require_relative "generate_host_authorization"
host_authorization = generate_host_authorization(root, read, parts)
extract.call("actionpack-8.1.4/lib/action_dispatch/http/url.rb", "URL", %i[raw_host_with_port host])
extract.call("rack-2.2.24/lib/rack/request.rb", "Env", %i[get_header set_header])
read.call("fast_blank-1.0.1/ext/fast_blank/fast_blank.c")
response_middleware = generate_response_middleware(root)
# Actual Actionpack middleware methods and Request's env-slot declaration
# anchor the Ruby-family framework binding; they are not oracle payload input.
extract.call("actionpack-8.1.4/lib/action_dispatch/middleware/request_id.rb", "RequestId", %i[initialize call make_request_id internal_request_id])
request_source = read.call("actionpack-8.1.4/lib/action_dispatch/http/request.rb")
request_id_key = walk.call(Prism.parse(request_source).value) { |node| node.is_a?(Prism::ConstantWriteNode) && node.name == :ACTION_DISPATCH_REQUEST_ID }
raise "original request ID env key changed" unless request_id_key && request_id_key.value.slice == '"action_dispatch.request_id"'
parts << {source: "actionpack-8.1.4/lib/action_dispatch/http/request.rb", start_byte: request_id_key.location.start_offset,
  end_byte: request_id_key.location.end_offset, text_sha256: Digest::SHA256.hexdigest(request_id_key.slice)}
request_id_binding = %w[roundhouse/runtime/ruby/action_dispatch/request_id.rb roundhouse/runtime/spinel/inprocess_controller.rb].to_h do |name|
  [name, Digest::SHA256.file(File.join(root, name)).hexdigest]
end
shared_components = %w[portable_redis_connection.rb portable_profiler_request.rb portable_profiler_middleware.rb portable_profiler_bootstrap.rb portable_profiler_declarations.rb portable_request_processing.rb portable_json_response_middleware.rb portable_discourse_request_id_middleware.rb portable_cors_middleware.rb portable_host_authorization.rb portable_remote_ip.rb portable_json_ingress.rb portable_json_profile_middleware.rb portable_query_cache_boundary.rb portable_latest_request_stack.rb].to_h do |name|
  ["compat/framework/#{name}", Digest::SHA256.file(File.join(root, "fidelity/compat/framework", name)).hexdigest]
end
query_cache_hook_source = "activerecord-8.1.4/lib/active_record/query_cache.rb"
read.call(query_cache_hook_source)
extract.call(query_cache_hook_source, "ExecutorHooks", %i[run complete])
query_cache_runtime = %w[roundhouse/runtime/ruby/active_record/query_cache_scope.rb roundhouse/runtime/ruby/active_record/query_cache_scope.rbs].to_h do |name|
  [name, Digest::SHA256.file(File.join(root, name)).hexdigest]
end
# Actual source contracts for the newly composed context/session portion.
context_query_sources = %w[activerecord-8.1.4/lib/active_record/connection_adapters/abstract/connection_pool.rb activesupport-8.1.4/lib/active_support/dependencies/interlock.rb activesupport-8.1.4/lib/active_support/concurrency/share_lock.rb railties-8.1.4/lib/rails/application/finisher.rb activesupport-8.1.4/lib/active_support/execution_context.rb activesupport-8.1.4/lib/active_support/current_attributes.rb activesupport-8.1.4/lib/active_support/railtie.rb activesupport-8.1.4/lib/active_support/event_reporter.rb activerecord-8.1.4/lib/active_record/asynchronous_queries_tracker.rb]
context_query_sources.each { |name| read.call(name) }
context_query_runtime = %w[roundhouse/runtime/ruby/active_record/connection_pool_executor.rb roundhouse/runtime/ruby/active_record/connection_pool_executor.rbs roundhouse/runtime/ruby/active_record/connection.rb roundhouse/runtime/ruby/active_record/connection.rbs roundhouse/runtime/spinel/active_record_db_config.rb roundhouse/runtime/ruby/active_support_interlock.rb roundhouse/runtime/ruby/active_support_interlock.rbs roundhouse/runtime/ruby/active_support_reporters.rb roundhouse/runtime/ruby/active_support_reporters.rbs roundhouse/runtime/ruby/active_record/asynchronous_queries_tracker.rb roundhouse/runtime/ruby/active_record/asynchronous_queries_tracker.rbs roundhouse/runtime/ruby/active_record/request_query_scope.rb roundhouse/runtime/ruby/active_record/request_query_scope.rbs].to_h do |name|
  [name, Digest::SHA256.file(File.join(root, name)).hexdigest]
end
application_sources = %w[config/initializers/006-mini_profiler.rb config/discourse_defaults.conf lib/middleware/processing_request.rb].to_h do |name|
  bytes = File.binread(File.join(root, "discourse", name))
  target = File.join(root, "fidelity/source/discourse", name)
  raise "immutable application profiler source changed" if File.exist?(target) && File.binread(target) != bytes
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, bytes) unless File.exist?(target)
  [name, Digest::SHA256.hexdigest(bytes)]
end
manifest = {profile: "original5 profiler records/config/owned injected Redis core; NOT full middleware acceptance",
  source_sha256: hashes, application_source_sha256: application_sources, selected_spans: parts,
  response_middleware: response_middleware,
  host_authorization: host_authorization,
  remote_ip: remote_ip,
  json_profile_middleware: json_profile_middleware,
  context_and_queries_lifecycle: {sources: context_query_sources, runtime_sha256: context_query_runtime,
    transformations: ["CurrentAttributes accessors remain statically lowered; registry holds actual typed instances per execution-context frame",
      "Separate typed context/instance stacks preserve Rails push/pop/flush behavior",
      "Session AtomicBoolean/read-write-lock replaced by mutex/condition-variable protected active state and real reader/finalizer exclusion",
      "Original run order interlock/context/cache/queries and FIFO complete context/cache/queries/pool then interlock; reentrant inner scope does not own enclosing lifecycle",
      "Single actual backend pool; real SQL notifications and Base.connection bind the stateless AR facade lease; source closed/nonjoinable completion releases that lease, never another owner's Db checkout or readonly transaction pin",
      "Running interlock stores real strongly held thread/share records under a mutex/condition-variable; unloading waits for final reader release and readers wait behind writer; share upgrades/yield_shares/reloading profile explicitly unsupported"],
    supported_running_interlock_accepted: true, full_reloading_interlock_accepted: false, single_backend_facade_pool_completion_accepted: true, all_executor_hooks_accepted: false,
    observed_context_or_query_results_as_inputs: false},
  query_cache_lifecycle: {source: query_cache_hook_source, runtime_sha256: query_cache_runtime,
    body_contract: "eager Array[String]; close-driven completion, not middleware return",
    supported_profile: "single active readonly database configuration; previously enabled cache ownership retained",
    all_executor_hooks_accepted: false, observed_cache_contents_as_inputs: false},
  request_id_framework_binding: {implementations_sha256: request_id_binding,
    original_class: "ActionDispatch::RequestId", actual_class: "PortableDiscourseRequestIdMiddleware",
    transformations: ["Request#get_header/set_header/request_id are direct reads/writes of the identical original env slot",
      "Generic framework retains Rails Unicode blank; actual Discourse subclass uses original fast_blank context before sanitization"],
    full_stack_accepted: false},
  shared_components_sha256: shared_components,
  candidate: "compat/framework/rack_mini_profiler_core.rb", candidate_sha256: Digest::SHA256.hexdigest(text),
  transformations: ["Explicit static Config/Context fields from actual defaults; no effective runtime values",
    "Same-distribution base36 ID generation", "ERB HTML escaping uses underlying CGI primitive",
    "RedisStore implicit global connection refuses; actual injected-connection methods retained",
    "Snapshot fields use literal original TLS key and actual first-field Hash initialization; no dummy entries or changed API"],
  native_request_accepted: false, page_accepted: false, captured_values_as_inputs: false}
manifest_path = File.join(root, "fidelity/progressive/stage4_request/PROFILER_SOURCE_MANIFEST.json")
File.write(manifest_path, JSON.pretty_generate(manifest) + "\n")
puts path

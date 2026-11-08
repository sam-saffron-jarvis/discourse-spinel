# frozen_string_literal: true
# Diagnostic observer of the GENUINE original no-plugin boot. No method wrapper,
# generated application body, provider replacement or captured native inputs.
require "json"
require "digest"
raise "requires original no-plugin profile" unless ENV["LOAD_PLUGINS"] == "0"
root = File.expand_path("../../discourse", __dir__)
gem_root = File.expand_path("../../run/bundle/ruby/4.0.0/gems/rails_multisite-9.0.0/lib", __dir__)
files = ["config/initializers/002-freedom_patches.rb", "config/initializers/005-site_settings.rb", "lib/freedom_patches/rails_multisite.rb"].map { |path| File.join(root, path) }
files += Dir[File.join(gem_root, "rails_multisite/connection_management{,/*}.rb")].sort
# Source-labelled require ATTEMPTS, every iteration, not inferred success or
# a sampled substitute for the full cold-provider trace. Read the original
# initializer's local argument syntax; never replace or invoke its callback.
require_locals = File.readlines(files.first).each_with_index.filter_map do |line, index|
  match = line.match(/\brequire\((\w+)\)/)
  [index + 1, match[1].to_sym] if match
end.to_h
require_attempts = []
patch_census = Dir[File.join(root, "lib/freedom_patches/*.rb")].sort
owner = nil
sequence = 0
lifecycle = []
lines = {}
returns = {}
counts = Hash.new(0)
watch = [:instance, :current_db, :each_connection, :each_active_connection, :safe_each_connection]
trace = TracePoint.new(:class, :end, :line, :call, :return, :b_call) do |event|
  next unless files.include?(event.path)
  sequence += 1
  key = [event.path, event.lineno, event.event, event.method_id]
  raise "unbounded selected source points" if !counts.key?(key) && counts.length >= 4096
  counts[key] += 1
  if event.event == :line && event.path == files.first && (argument = require_locals[event.lineno]) &&
      event.binding.local_variable_defined?(argument)
    target = event.binding.local_variable_get(argument)
    if target.is_a?(String)
      raise "require target escaped original freedom-patch census" unless patch_census.include?(target)
      raise "unbounded initializer require attempts" if require_attempts.length >= 256
      require_attempts << {order: sequence, source: [event.path, event.lineno], argument: argument,
                          target: target, safe_each_present: owner && owner.respond_to?(:safe_each_connection)}
    end
  end
  if [:class, :end].include?(event.event) && event.self.is_a?(Class) && event.self.name == "RailsMultisite::ConnectionManagement"
    owner ||= event.self
    raise "namespace class object replaced" unless owner.equal?(event.self)
    raise "unbounded namespace lifecycle" if lifecycle.length >= 32
    lifecycle << {order: sequence, event: event.event, source: [event.path, event.lineno],
                  same_namespace_object: owner.equal?(event.self), current_db_present: event.self.respond_to?(:current_db),
                  default_present: event.self.const_defined?(:DEFAULT, false),
                  safe_each_present: event.self.respond_to?(:safe_each_connection)}
  elsif event.event == :return && watch.include?(event.method_id)
    # Aggregate EVERY selected return's classes, not saved values or a sampled
    # full-provider trace. This observer does not replace the existing cold trace.
    value = event.return_value
    bucket = [event.path, event.method_id, value.class.name, value.is_a?(Module)]
    raise "unbounded return type domain" if !returns.key?(bucket) && returns.length >= 32
    returns[bucket] = returns.fetch(bucket, 0) + 1
  elsif [:line, :b_call].include?(event.event) && files.first(2).include?(event.path)
    # Explicit unique source-point coverage with exact execution counts above;
    # not an assertion that all iterations have been archived individually.
    next if lines.key?(key)
    raise "unbounded initializer source points" if lines.length >= 64
    klass = Object.const_defined?(:RailsMultisite) && RailsMultisite.const_defined?(:ConnectionManagement, false) ? RailsMultisite::ConnectionManagement : nil
    lines[key] = {order: sequence, source: [event.path, event.lineno], event: event.event,
                  same_namespace_object: klass && owner && owner.equal?(klass),
                  safe_each_present: klass && klass.respond_to?(:safe_each_connection)}
  end
end
begin
  trace.enable
  load File.join(__dir__, "core_no_plugins_oracle.rb")
ensure
  trace.disable
  puts "FIDELITY_CORE_MULTISITE " + JSON.generate({
    scope: "original source namespace/initializer/callable-provenance diagnostic ONLY; not native inputs or full effect trace",
    successful_oracle: $!.nil?, lifecycle: lifecycle, initializer_points: lines.values,
    initializer_require_attempts: require_attempts,
    freedom_patch_source_census: patch_census.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
    source_point_execution_counts: counts.map { |key, count| {source: key.first(2), event: key[2], method: key[3], count: count} },
    all_selected_return_types: returns.map { |key, count| {source: key[0], method: key[1], result_class: key[2], module_value: key[3], count: count} },
    final_same_namespace_object: owner && defined?(RailsMultisite::ConnectionManagement) && owner.equal?(RailsMultisite::ConnectionManagement),
    callable_descriptors: defined?(RailsMultisite::ConnectionManagement) ? watch.to_h { |name|
      method = RailsMultisite::ConnectionManagement.method(name)
      [name, {owner: method.owner.name, source: method.source_location, arity: method.arity, parameters: method.parameters}]
    } : {},
    source_sha256: files.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
  })
end

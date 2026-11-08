# frozen_string_literal: true
# TEST-only observations of real no-plugin boot/provider execution. No method
# wrappers, changed providers, captured-value inputs or substituted callbacks.
require "json"
require "digest"
raise "provider trace requires original no-plugin profile" unless ENV["LOAD_PLUGINS"] == "0"
base = File.expand_path("../../discourse", __dir__)
packages = %w[mini_sql-1.6.0 rails_multisite-9.0.0].map { |name|
  File.expand_path("../../run/bundle/ruby/4.0.0/gems/#{name}", __dir__) + "/"
}
core = %w[lib/mini_sql_multisite_connection.rb lib/site_settings/db_provider.rb config/initializers/000-mini_sql.rb].map { |name| File.join(base, name) }
events = []
evaluated_paths = []
accessor_locations = packages.flat_map { |root|
  Dir[File.join(root, "lib/mini_sql/**/deserializer_cache.rb")].flat_map { |path|
    File.readlines(path).each_with_index.filter_map { |line, index|
      [path, index + 1] if line.include?("attr_accessor(*fields)")
    }
  }
}
trace = TracePoint.new(:line, :call, :return, :c_call, :c_return, :class, :end, :script_compiled) do |event|
  path = event.path
  next unless core.include?(path) || packages.any? { |root| path.start_with?(root) } || evaluated_paths.include?(path)
  next if event.event == :line && !accessor_locations.include?([path, event.lineno])
  if [:c_call, :c_return].include?(event.event)
    next unless [:new, :attr_accessor, :include, :extend, :instance_eval, :type_map=, :add_coder, :rm_coder, :getvalue, :fields, :exec, :exec_params].include?(event.method_id)
  end
  raise "unbounded original core provider trace" if events.length >= 50_000
  row = {order: events.length + 1, event: event.event, method: event.method_id,
         source: [path, event.lineno], receiver_class: event.self.class.name,
         receiver_module: event.self.is_a?(Module) ? event.self.name : nil}
  if [:return, :c_return].include?(event.event)
    value = event.return_value
    row[:result_class] = value.class.name
    row[:result_module_name] = value.name if value.is_a?(Module)
  end
  if event.event == :line && accessor_locations.include?([path, event.lineno])
    # Ruby 4 intentionally supplies no Binding on C-call events. The
    # original Ruby line immediately before attr_accessor has its real frame.
    fields = event.binding.local_variable_get(:fields)
    raise "unexpected row field domain" unless fields.is_a?(Array) && fields.all? { |field| field.is_a?(String) }
    row[:observed_row_fields] = fields.dup
    row[:anonymous_row_class] = event.self.is_a?(Class) && event.self.name.nil?
  end
  if event.event == :script_compiled && event.eval_script
    row[:evaluated_source_sha256] = Digest::SHA256.hexdigest(event.eval_script)
    row[:evaluated_source_bytes] = event.eval_script.bytesize
    row[:evaluated_path] = event.instruction_sequence.path
    evaluated_paths << row[:evaluated_path] unless evaluated_paths.include?(row[:evaluated_path])
  end
  events << row
end
trace.enable
begin
  load File.join(__dir__, "core_no_plugins_oracle.rb")
ensure
  trace.disable
  puts "FIDELITY_CORE_PROVIDER_TRACE " + JSON.generate({
    scope: "original no-plugin cold boot/provider call-order/type/row-factory observations ONLY; never native inputs",
    successful_oracle: $!.nil?, events: events,
    loaded_provider_sources: $LOADED_FEATURES.select { |path| packages.any? { |root| path.start_with?(root) } }.sort,
    loaded_provider_source_hashes: $LOADED_FEATURES.select { |path| packages.any? { |root| path.start_with?(root) } && File.file?(path) }.sort.to_h { |path|
      [path, Digest::SHA256.file(path).hexdigest]
    },
  })
end

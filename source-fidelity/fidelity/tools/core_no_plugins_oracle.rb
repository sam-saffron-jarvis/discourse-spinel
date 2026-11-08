# frozen_string_literal: true
# TEST-only no-plugin boot attestation. Does not replace any application method.
raise "core milestone requires LOAD_PLUGINS=0 before boot" unless ENV["LOAD_PLUGINS"] == "0"
plugin_root = File.expand_path("plugins") + "/"
compiled_plugins = []
trace = TracePoint.new(:script_compiled) do |event|
  path = event.instruction_sequence&.path
  next unless path && File.expand_path(path).start_with?(plugin_root)
  compiled_plugins << path
  raise "core-only boot compiled a plugin source: #{path}"
end
begin
  trace.enable
  require_relative "oracle"
ensure
  trace.disable
end
loaded_plugins = $LOADED_FEATURES.select { |path| File.expand_path(path).start_with?(plugin_root) }
raise "actual GlobalSetting did not disable loading" if GlobalSetting.load_plugins?
raise "plugin instances loaded" unless Discourse.plugins.empty?
raise "plugin sources loaded" unless loaded_plugins.empty? && compiled_plugins.empty?
puts "FIDELITY_CORE_NO_PLUGINS " + JSON.generate({
  profile: "original-core-no-plugins", load_plugins_env: ENV.fetch("LOAD_PLUGINS"),
  load_plugins: GlobalSetting.load_plugins?, plugins_to_load: GlobalSetting.plugins_to_load,
  plugin_instance_names: Discourse.plugins.map(&:name),
  compiled_plugin_sources: compiled_plugins, loaded_plugin_sources: loaded_plugins,
  original_configuration: %w[app/models/global_setting.rb config/application.rb].to_h { |path|
    [path, Digest::SHA256.file(path).hexdigest]
  },
  switch_source: GlobalSetting.method(:load_plugins?).source_location,
})

# frozen_string_literal: true
# Observation-only wrapper around the existing real, guarded, read-only Rails
# oracle. No plugin method/callback/configuration is wrapped, replaced or seeded.
require "json"
require "pathname"
base = File.expand_path("../../discourse", __dir__)
paths = %w[discourse-assign discourse-events discourse-solved].map { |name| File.join(base, "plugins", name, "plugin.rb") }
configuration_paths = paths.map { |path| File.join(File.dirname(path), "config/settings.yml") }
observed_provider_classes = []
events = []
order = 0
relative = lambda do |path|
  path&.start_with?(base + "/") ? path.delete_prefix(base + "/") : path
end
block_info = lambda do |block|
  next nil unless block.is_a?(Proc)
  owner = block.binding.receiver
  captures = {}
  # Names and callable source locations only; NEVER capture arbitrary values.
  block.binding.local_variables.each do |name|
    value = block.binding.local_variable_get(name)
    captures[name] = value.source_location if value.is_a?(Proc)
  end
  { source: block.source_location, parameters: block.parameters,
    owner_class: owner.class.name, owner_module: owner.is_a?(Module) ? owner.name : nil,
    captured_callables: captures }
end
trace = TracePoint.new(:call, :return, :c_call, :b_call) do |event|
  method = event.method_id
  original_plugin_block = event.event == :b_call && paths.include?(event.path)
  next unless original_plugin_block || [:activate!, :after_initialize, :notify_after_initialize, :reloadable_patch,
    :enabled_site_setting, :instance_eval, :add_custom_filter, :register, :load_settings, :provider].include?(method)
  site_setting = event.defined_class&.name == "SiteSettingExtension" && event.self.is_a?(Class) && event.self.name == "SiteSetting"
  configuration_file = event.binding.local_variable_get(:file) if site_setting && event.event == :call && method == :load_settings
  configuration = configuration_paths.include?(configuration_file)
  provider = site_setting && event.event == :return && method == :provider
  if provider
    provider_class = event.return_value.class.name
    next if observed_provider_classes.include?(provider_class)
    observed_provider_classes << provider_class
  end
  plugin = event.defined_class&.name == "Plugin::Instance"
  path = plugin || method == :instance_eval ? event.self.instance_variable_get(:@path) : nil
  selected = paths.include?(path)
  topic_filter = event.event == :call && method == :add_custom_filter && event.self.is_a?(Class) && event.self.name == "TopicQuery"
  solved_register = event.event == :call && method == :register && event.self.is_a?(Class) && event.self.name == "DiscourseSolved::RegisterFilters"
  watched = selected && ((event.event == :call && [:activate!, :after_initialize, :notify_after_initialize, :reloadable_patch, :enabled_site_setting].include?(method)) ||
    (event.event == :return && [:activate!, :notify_after_initialize].include?(method)) ||
    (event.event == :c_call && method == :instance_eval))
  next unless watched || topic_filter || solved_register || original_plugin_block || configuration || provider
  # Getter calls of enabled_site_setting are NOT configuration declarations.
  setting = event.binding.local_variable_get(:setting) if method == :enabled_site_setting
  next if method == :enabled_site_setting && !setting.is_a?(Symbol)
  order += 1
  row = { order: order, event: event.event, method: method, thread: Thread.current.object_id,
          source: [relative.call(event.path), event.lineno], plugin_source: relative.call(path) }
  row[:configured_setting_name] = setting.to_s if setting.is_a?(Symbol)
  row[:configuration_source] = relative.call(configuration_file) if configuration
  # Type identity ONLY, never effective setting/provider/cache contents.
  row[:runtime_provider_class] = provider_class if provider
  if method == :after_initialize && event.event == :call
    row[:callback] = block_info.call(event.binding.local_variable_get(:block))
  elsif method == :reloadable_patch && event.event == :call
    # Original method has an implicit block (yield), not an &block local.
    # Observe caller and later b_call events without materializing/replacing it.
    row[:implicit_block] = true
    row[:original_callers] = caller_locations.filter_map do |location|
      [relative.call(location.path), location.lineno] if paths.include?(location.path)
    end
  elsif topic_filter
    row[:filter_name] = event.binding.local_variable_get(:key).to_s
    row[:callback] = block_info.call(event.binding.local_variable_get(:blk))
  end
  events << row
end
trace.enable
begin
  # Original oracle installs its own endpoint/read-only PG guards and owns
  # cleanup. Its consumer/probe args remain unchanged; this is normal boot,
  # NOT the consumed private-PostgreSQL HTML experiment.
  load File.join(__dir__, "oracle.rb")
ensure
  trace.disable
  puts "FIDELITY_PLUGIN_ACTIVATION " + JSON.generate({
    scope: "actual original Rails activation/registration observations ONLY; no native seed or activation acceptance",
    successful_oracle: $!.nil?, events: events,
    loaded_plugin_ruby_sources: $LOADED_FEATURES.select do |feature|
      feature.end_with?(".rb") && paths.any? { |entry| feature.start_with?(File.dirname(entry) + "/") }
    end.map { |feature| relative.call(feature) }.sort,
  })
end

# frozen_string_literal: true
# CRuby-only original-method acquisition adapter: it reads FRESH actual store
# state/declarations. No supplied settings values, forced flags, oracle payloads,
# fake PG rows, original Rails request or initialization callbacks are involved.
module OriginalHtmlStageSource
  class LiveProviderView
    attr_reader :defaults
    def initialize(store, site)
      @store, @site = store, site
      @definitions = store.instance_variable_get(:@definitions)
      @values = store.instance_variable_get(:@values).fetch(site)
      @defaults = DefaultsProvider.new(self)
      @definitions.each { |name, definition| @defaults.load_setting(name, definition.default_value, nil) }
    end
    def current; @values.transform_keys(&:to_sym); end
    def setting_modified_from_default?(name); @store.setting_modified_from_default?(name, @site); end
    def promote_upcoming_changes_on_status; @store.get("promote_upcoming_changes_on_status", @site); end
    def plugins
      @definitions.each_with_object({}) { |(name, definition), map| map[name.to_sym] = definition.options["plugin"] if definition.options.key?("plugin") }
    end
    def upcoming_change_metadata
      @definitions.each_with_object({}) do |(name, definition), map|
        metadata = definition.options["upcoming_change"]
        next unless metadata
        map[name.to_sym] = metadata.transform_keys(&:to_sym).merge(status: metadata.fetch("status").to_sym)
      end
    end
    def upcoming_change_default_overrides
      @definitions.each_with_object({}) do |(name, definition), map|
        override = definition.options["upcoming_change_default_override"]
        next unless override
        map[name.to_sym] = {upcoming_change: override.fetch("upcoming_change").to_sym, new_default: override.fetch("new_default")}
      end
    end
    def type_supervisor; self; end
    def dependencies
      @definitions.each_with_object({}) { |(name, definition), map| map[name.to_sym] = definition.options["depends_on"] if definition.options.key?("depends_on") }
    end
    def dependency_values; raise "unsupported original-method dependency values"; end
  end
  class OriginalRequestView
    def initialize(request); @request = request; end
    # Real Actionpack MIME object, not a fake String#json? implementation.
    def format; Mime::Type.lookup_by_extension(@request.format); end
    def xhr?; @request.xhr?; end
    def get?; @request.get?; end
  end
  def self.compare(request, controller, stored)
    view = LiveProviderView.new(SiteSetting.portable_store, SiteSetting.portable_site)
    UpcomingChanges.live_provider = view
    enabled = UpcomingChanges.enabled?(:enable_unified_new)
    view.defaults.activate_upcoming_change_override(:enable_unified_new) if enabled
    expected_menu = view.defaults.all[:top_menu]
    expected_menu = view.current[:top_menu] if view.setting_modified_from_default?(:top_menu)
    # Global menu shadows are handled by source provider/config precedence in the
    # candidate; refuse that unproved reference-adapter profile, never invent it.
    shadows = SiteSetting.portable_store.instance_variable_get(:@shadows).fetch(SiteSetting.portable_site)
    raise "unsupported isolated-reference global menu shadow" if shadows.include?("top_menu")
    raise "original UpcomingChanges/DefaultsProvider menu mismatch" unless SiteSetting.top_menu == expected_menu
    marker = Marker.new(OriginalRequestView.new(request))
    marker.preload_json
    raise "original HTML preload marker mismatch" unless marker.value == controller.instance_variable_get(:@_preloaded)
    actual = controller.instance_variable_get(:@application_layout_preloader)
    original = Preloader.new(guardian: controller.guardian, theme_id: actual.instance_variable_get(:@theme_id),
      theme_target: actual.instance_variable_get(:@theme_target), login_method: actual.instance_variable_get(:@login_method))
    fresh_json = JSON.generate(ActiveSupport::JSON.jsonable(TopicListSerializer.new(controller.html_stage_list, scope: controller.guardian).as_json))
    original.store_preloaded(controller.html_stage_list.preload_key, fresh_json)
    raise "original derived list storage mismatch" unless original.values == stored
    {original_upcoming_and_defaults: true, original_preload_marker: true, original_constructor_and_storage: true,
      context: "fresh live reads + source declarations, not full Rails HTML or settings initialization"}
  end
end

class LatestHtmlStageProbe
  def self.compare_isolated_original(request, controller, stored)
    OriginalHtmlStageSource.compare(request, controller, stored)
  end
end

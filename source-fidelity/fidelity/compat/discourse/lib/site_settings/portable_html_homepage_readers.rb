# frozen_string_literal: true
# Necessary read contract for the actual HTML homepage, NOT scalar admission or
# an upcoming-change activation implementation. Unknown profiles still refuse.
module SiteSettings
  class PortableReadStore
    def get_top_menu_for_html(site, statuses)
      definition = @definitions["top_menu"]
      change = @definitions["enable_unified_new"]
      raise PortableUnsupported, "unsupported HTML top-menu declarations" unless definition && change
      override = definition.options["upcoming_change_default_override"]
      metadata = change.options["upcoming_change"]
      unless definition.data_type == 8 && !definition.themeable? && override.is_a?(Hash) &&
          override["upcoming_change"] == "enable_unified_new" && override["new_default"].is_a?(String) &&
          change.data_type == 5 && metadata.is_a?(Hash) && !change.options.key?("depends_on") &&
          !change.options.key?("plugin") && !definition.options.key?("locale_default")
        raise PortableUnsupported, "unsupported HTML top-menu default override profile"
      end
      refresh!(site) unless @mutex.synchronize { @values.key?(site) }
      values = @mutex.synchronize { @values[site] }
      modified = @mutex.synchronize { @modified[site] }
      shadows = @mutex.synchronize { @shadows[site] }
      # Source precedence: actual configured/DB menu overrides the default.
      if modified.key?("top_menu") || shadows.include?("top_menu")
        value = values["top_menu"]
        raise PortableUnsupported, "unsupported HTML top-menu value type" unless value.is_a?(String)
        return value
      end
      raise PortableUnsupported, "unsupported globally shadowed HTML upcoming change" if shadows.include?("enable_unified_new")
      status = metadata["status"].to_s
      promotion = get("promote_upcoming_changes_on_status", site).to_s
      status_value = statuses[status.to_sym]
      promotion_value = statuses[promotion.to_sym]
      raise PortableUnsupported, "unsupported HTML upcoming-change status" unless status_value && promotion_value
      enabled = false
      # UpcomingChanges.enabled?: this core declaration has no plugin/dependencies.
      # A real stored opt-in/out wins unless permanent; otherwise promotion then
      # the declared default. No getter/setter/callback is forced or skipped.
      if modified.key?("enable_unified_new") && status != "permanent"
        enabled = values["enable_unified_new"]
        raise PortableUnsupported, "unsupported HTML upcoming-change value type" unless enabled == true || enabled == false
      elsif status_value >= promotion_value || status == "permanent"
        enabled = true
      else
        enabled = change.default_value
        raise PortableUnsupported, "unsupported HTML upcoming-change default type" unless enabled == true || enabled == false
      end
      (enabled ? override["new_default"] : definition.default_value).to_s
    end
  end
end

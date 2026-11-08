# frozen_string_literal: true
# One actual current-helper getter, NOT generic scalar/upcoming admission.
module SiteSettings
  class PortableReadStore
    def get_markdown_endpoints_for_layout(site, statuses)
      definition = @definitions['enable_markdown_endpoints']
      raise PortableUnsupported, 'markdown declaration missing' unless definition
      metadata = definition.options['upcoming_change']
      unless definition.data_type == 5 && !definition.themeable? && metadata.is_a?(Hash) && !definition.options.key?('plugin') && !definition.options.key?('depends_on') && !definition.options.key?('upcoming_change_default_override') && !definition.options.key?('portable_source_override') && !definition.options.key?('mandatory_values') && !definition.options.key?('enum')
        raise PortableUnsupported, 'unsupported markdown upcoming getter profile'
      end
      refresh!(site) unless @mutex.synchronize { @values.key?(site) }
      values = @mutex.synchronize { @values[site] }
      modified = @mutex.synchronize { @modified[site] }
      shadows = @mutex.synchronize { @shadows[site] }
      raise PortableUnsupported, 'unsupported shadowed markdown getter profile' if shadows.include?('enable_markdown_endpoints')
      status = metadata['status'].to_s
      promotion = get('promote_upcoming_changes_on_status', site).to_s
      status_value = statuses[status.to_sym]
      promotion_value = statuses[promotion.to_sym]
      raise PortableUnsupported, 'unknown markdown upcoming status' unless status_value && promotion_value
      value = if modified.key?('enable_markdown_endpoints') && status != 'permanent'
        values['enable_markdown_endpoints']
      elsif status_value >= promotion_value || status == 'permanent'
        true
      else
        definition.default_value
      end
      raise PortableUnsupported, 'markdown upcoming result is not Boolean' unless value == true || value == false
      value
    end
  end
end
module MarkdownEndpointLayoutRead
  def enable_markdown_endpoints(scoped_to = nil)
    raise ArgumentError, 'unsupported scoped markdown getter' unless scoped_to.nil?
    portable_store.get_markdown_endpoints_for_layout(portable_site, HtmlUpcomingStatuses::VALUES)
  end
  def enable_markdown_endpoints?(scoped_to = nil); enable_markdown_endpoints(scoped_to); end
end
SiteSetting.extend(MarkdownEndpointLayoutRead)

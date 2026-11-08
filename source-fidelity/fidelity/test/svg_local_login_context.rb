# frozen_string_literal: true
module SvgLocalLoginRead
  def self.reset; @dependencies = {}; nil; end
  def self.dependencies; @dependencies ||= {}; end
  def self.note(name, value)
    raise TypeError, 'SVG local-login dependency not Boolean' unless value == true || value == false
    dependencies[name] = value
    value
  end
  def self.enabled
    reset
    SiteSetting.portable_store.svg_local_login_enabled(SiteSetting.portable_site, HtmlUpcomingStatuses::VALUES)
  end
  def self.read
    value = enabled.to_s
    value += '-wrong' if ENV.fetch('FIDELITY_SVG_LOCAL_LOGIN_FAULT', '') == 'wrong-result'
    value
  end
end
module SiteSettings
  class PortableReadStore
    def svg_local_login_enabled(site, statuses)
      name = 'enable_local_logins_via_code'
      definition = @definitions[name]
      raise PortableUnsupported, 'missing SVG local-login declaration' if definition.nil?
      options = definition.options
      metadata = options['upcoming_change']
      raise PortableUnsupported, 'unsupported SVG local-login profile' unless definition.data_type == 5 && !definition.themeable? && metadata.is_a?(Hash) && options['depends_on'] == ['enable_local_logins', 'enable_local_logins_via_email'] && !options.key?('depends_on_values') && !options.key?('plugin') && !options.key?('portable_source_override') && !options.key?('upcoming_change_default_override')
      raise PortableUnsupported, 'unsupported shadowed SVG local login' if svg_shadowed?(name, site)
      first = SiteSetting.enable_local_logins
      first = 'invalid-Boolean' if ENV.fetch('FIDELITY_SVG_LOCAL_LOGIN_FAULT', '') == 'wrong-dependency-type'
      return false unless SvgLocalLoginRead.note('enable_local_logins', first)
      unless ENV.fetch('FIDELITY_SVG_LOCAL_LOGIN_FAULT', '') == 'skip-dependency'
        return false unless SvgLocalLoginRead.note('enable_local_logins_via_email', SiteSetting.enable_local_logins_via_email)
      end
      values = @mutex.synchronize { @values[site] }
      modified = @mutex.synchronize { @modified[site] }
      status = metadata['status'].to_s
      promotion = get('promote_upcoming_changes_on_status', site).to_s
      status_value = statuses[status.to_sym]
      promotion_value = statuses[promotion.to_sym]
      raise PortableUnsupported, 'unknown SVG local-login status' unless status_value && promotion_value
      result = if modified.key?(name) && status != 'permanent'
        values[name]
      elsif status_value >= promotion_value || status == 'permanent'
        true
      else
        definition.default_value
      end
      raise PortableUnsupported, 'SVG local-login result not Boolean' unless result == true || result == false
      result
    end
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'enable_local_logins_via_code' ? 'acquired_local_login_change' : additional_kind_without_local_login(name)
  end
  def self.read(name, warn: true)
    name == 'enable_local_logins_via_code' ? SvgLocalLoginRead.read : read_without_local_login(name, warn: warn)
  end
end
module SvgLocalLoginViewProtocol
  def svg_local_login_stage_observation
    record = svg_default_stage_observation
    first = SiteSetting.enable_local_logins
    expected = first ? ['enable_local_logins', 'enable_local_logins_via_email'] : ['enable_local_logins']
    dependencies = SvgLocalLoginRead.dependencies.dup
    raise 'SVG source dependency order/call omitted' unless dependencies.keys == expected
    result = SvgLocalLoginRead.enabled
    digest = Digest::SHA256.hexdigest(result.to_s)
    raise 'SVG local-login upcoming result changed' unless SvgSettingsRead.records['enable_local_logins_via_code'] == digest
    record[:svg_local_login] = {dependencies: dependencies, value_digest: digest, source_dependencies_evaluated: true}
    record
  end
end
class ListBodyContext
  include SvgLocalLoginViewProtocol
  def observation; svg_local_login_stage_observation; end
end

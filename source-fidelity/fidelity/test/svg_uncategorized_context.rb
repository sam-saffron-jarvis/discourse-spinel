# frozen_string_literal: true
require_relative 'svg_uncategorized_source'
module SvgUncategorizedRead
  def self.enabled
    SiteSetting.portable_store.get_svg_uncategorized_change(SiteSetting.portable_site, HtmlUpcomingStatuses::VALUES)
  end
  def self.read
    value = enabled
    value = 'invalid-Boolean' if ENV.fetch('FIDELITY_SVG_UNCATEGORIZED_FAULT', '') == 'non-boolean'
    raise TypeError, 'SVG uncategorized getter result not Boolean' unless value == true || value == false
    text = value.to_s
    text += '-wrong' if ENV.fetch('FIDELITY_SVG_UNCATEGORIZED_FAULT', '') == 'wrong-result'
    text
  end
end
module SvgSettingsRead
  def self.additional_kind(name)
    name == 'remove_and_replace_uncategorized' ? 'acquired_uncategorized_change' : additional_kind_without_uncategorized(name)
  end
  def self.read(name, warn: true)
    name == 'remove_and_replace_uncategorized' ? SvgUncategorizedRead.read : read_without_uncategorized(name, warn: warn)
  end
end
module SvgUncategorizedViewProtocol
  def svg_uncategorized_stage_observation
    record = svg_local_login_stage_observation
    actual = SvgSettingsRead.records['remove_and_replace_uncategorized']
    raise 'SVG uncategorized upcoming getter changed' unless actual == Digest::SHA256.hexdigest(SvgUncategorizedRead.enabled.to_s)
    record[:svg_uncategorized] = {value_digest: actual, getter_only: true, setter_or_action_invoked: false}
    record
  end
end
class ListBodyContext
  include SvgUncategorizedViewProtocol
  def observation; svg_uncategorized_stage_observation; end
end

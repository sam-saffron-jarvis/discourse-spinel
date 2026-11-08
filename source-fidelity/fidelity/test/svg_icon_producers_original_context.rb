# frozen_string_literal: true
require 'active_support/core_ext/object/blank'
require_relative 'original_svg_icon_producers_source'
require_relative 'original_svg_icon_producers_metadata'
module SvgIconProducers
  def self.types; @original_types ||= OriginalSvgIconReadTypes.new; end
  def self.source_settings_icons; OriginalRequestSvgSource.settings_icons; end
  def self.source_badge_icons; OriginalRequestSvgSource.badge_icons; end
  def self.source_group_icons; OriginalRequestSvgSource.group_icons; end
end
module RequestSvgBootstrap
  def self.path(id)
    SvgIconProducers.note_entry
    OriginalRequestSvgSource.path(id)
  end
end
class OriginalListBodyContext
  include SvgIconProducersViewProtocol
  def observation; svg_icon_producers_stage_observation; end
end

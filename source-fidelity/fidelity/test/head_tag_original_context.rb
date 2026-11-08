# frozen_string_literal: true
require_relative 'original_head_tag_helpers'
class OriginalListBodyContext
  include OriginalHeadTagHelpers
  include HeadTagViewProtocol
  def observation; head_tag_stage_observation; end
end

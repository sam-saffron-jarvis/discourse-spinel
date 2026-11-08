# frozen_string_literal: true
require_relative 'original_core_preload_helpers'
class OriginalListBodyContext
  include OriginalCorePreloadHelpers
  include CorePreloadViewProtocol
  def observation; core_preload_stage_observation; end
end

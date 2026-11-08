# frozen_string_literal: true
require_relative 'original_client_setup_source'
class OriginalListBodyContext
  include OriginalClientSetupHelpers
  include ClientSetupPrefixViewProtocol
  def source_setup_tag_builder
    ActionView::Helpers::TagHelper.instance_method(:tag_builder).bind(self).call
  end
  def setup_builder_owned?(value); value.instance_variable_get(:@view_context).equal?(self); end
  def observation; client_setup_prefix_stage_observation; end
end

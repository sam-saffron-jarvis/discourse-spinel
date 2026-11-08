# frozen_string_literal: true
require_relative 'original_markdown_link_helpers'
require_relative 'original_markdown_modifier_dispatch'
class OriginalListBodyContext
  include OriginalMarkdownLinkHelpers
  include MarkdownLinkViewProtocol
  def tag(name = nil, options = nil, open = false, escape = true)
    metadata_tag_or_builder(name, options, open, escape)
  end
  def observation; markdown_link_stage_observation; end
end

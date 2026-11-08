# frozen_string_literal: true
require 'action_view/flows'
require_relative 'original_head_yield_source'
class OriginalListBodyContext
  include OriginalSourceHeadLayoutFor
  include HeadYieldViewProtocol
  def get(slot)
    raise ArgumentError, 'unsupported head flow read profile' unless slot == :head && @body_returned
    source = @head_output
    raise TypeError, 'captured head slot is not String' unless source.is_a?(String)
    unless @source_head_flow
      @head_flow_source = source.dup.freeze
      @source_head_flow = ActionView::OutputFlow.new
      @source_head_flow.set(:head, source)
    end
    raise ArgumentError, 'unsupported late/interleaved head capture' unless source == @head_flow_source
    @source_head_flow.get(slot)
  end
  def observation; head_yield_stage_observation; end
end

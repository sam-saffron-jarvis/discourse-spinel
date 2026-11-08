# frozen_string_literal: true
require_relative 'original_svg_wrapped_source'
module OriginalSvgWrappedSource
  class DuplicateTopicTitlesSiteSetting
    class << self
      alias source_wrap_without_observation wrap
      def wrap(value)
        result = source_wrap_without_observation(value)
        raise 'original wrapped enum construction failed' unless result.is_a?(String) && result.class == self::Value && result.class != String
        raise 'original wrapper predicate changed' unless [result.disallowed?, result.allowed_across_categories?, result.allowed?] == [value == self::DISALLOWED, value == self::ALLOWED_ACROSS_CATEGORIES, value == self::ALLOWED]
        puts 'FIDELITY_SVG_WRAPPED_REFERENCE ' + JSON.generate({wrapper_class: result.class.name, string_subclass: true, frozen: result.frozen?, real_source_wrap_executed: true})
        result
      end
    end
  end
end
module OriginalSvgSettingsReference
  class TypeView
    def get_enum_class(name)
      return OriginalSvgWrappedSource::DuplicateTopicTitlesSiteSetting if name.to_s == 'duplicate_topic_titles'
      get_enum_class_without_wrapped(name)
    end
  end
end
class OriginalListBodyContext
  include SvgWrappedViewProtocol
  def observation; svg_wrapped_stage_observation; end
end

# frozen_string_literal: true
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      return acquired_getter_value_without_uploaded_list(name) unless name == 'selectable_avatars'
      SvgUploadedListRead.assert_empty_input
      setup_methods(name.to_sym)
      singleton_class.alias_method(:svg_original_selectable_avatars, :selectable_avatars)
      define_singleton_method(:selectable_avatars) do |scoped_to = nil|
        SvgUploadedListRead.assert_empty_input
        value = svg_original_selectable_avatars(scoped_to)
        raise 'SVG source empty uploaded-image-list unexpectedly cached' if uploads.key?(:selectable_avatars)
        SvgUploadedListRead.note_array(value)
        value
      end
      selectable_avatars
    end
  end
end
class OriginalListBodyContext
  include SvgUploadedListViewProtocol
  def observation; svg_uploaded_list_stage_observation; end
end

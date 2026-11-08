# frozen_string_literal: true
module OriginalSvgSettingsReference
  class View
    def acquired_getter_value(name)
      return acquired_getter_value_without_objects(name) unless name == 'dsa_community_rules'
      setup_methods(:dsa_community_rules)
      singleton_class.alias_method(:svg_original_dsa_community_rules, :dsa_community_rules)
      define_singleton_method(:dsa_community_rules) do |scoped_to = nil|
        value = svg_original_dsa_community_rules(scoped_to)
        SvgObjectsRead.note(value)
        value
      end
      dsa_community_rules
    end
  end
end
class OriginalListBodyContext
  include SvgObjectsViewProtocol
  def observation; svg_objects_stage_observation; end
end

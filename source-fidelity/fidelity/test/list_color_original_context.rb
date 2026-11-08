# frozen_string_literal: true
require_relative "original_list_color"
# Original Theme belongs_to :color_scheme protocol, omitted from earlier JSON
# read roots. Resolve its real foreign key with the original default predicate.
class Theme
  def color_scheme
    id = color_scheme_id
    ColorScheme.where(remote_copy: false).find_by(id: id) unless id.nil?
  end
end
# The original lookup consumes only name/hex on the unsaved base palette.
# Its values are parsed by UNCHANGED original base_colors from pinned SCSS, not
# supplied/observed DB rows. No ActiveRecord persistence is bound here.
module OriginalListColors
  Color = Struct.new(:name, :hex)
  class BasePalette
    attr_reader :colors
    def initialize(values)
      @colors = values.map { |name, hex| Color.new(name, hex) }
    end
  end
  def self.base; BasePalette.new(base_colors); end
  def self.hex_cache; CategoryCacheBootstrap.layout_color_cache; end
  def self.find_by(**options); ::ColorScheme.where(remote_copy: false).find_by(**options); end
  def self.find_by_id(id); ::ColorScheme.where(remote_copy: false).find_by(id: id); end
end
module OriginalObservedLayoutColors
  include OriginalListColorHelpers
  def discourse_theme_color_meta_tags
    @events << "layout_color_cache_acquisition"
    super
  end
end
class OriginalListBodyContext
  include ListLayoutColorProtocol
  include OriginalObservedLayoutColors
end

# frozen_string_literal: true
# Source ThemeSvgSprite.where(...).pluck ONLY, not a record-model substitute.
# The original model has no default scopes; belongs_to is not traversed by pluck.
# Real generic ORM builds/binds/executes SELECT; any actual row refuses BEFORE
# using binary or other values. No hand-written data SQL or empty row supplied.
class SvgThemeSpriteRead < ActiveRecord::Base
  def self.table_name; 'theme_svg_sprites'; end
  def self._table_sql; ActiveRecord.adapter.quote_column_name(table_name); end
  def self._default_scope_where; {}; end
  def self.schema_columns; [:theme_id, :upload_id, :sprite]; end
  def self.schema_column_types; {theme_id: :integer, upload_id: :integer, sprite: :binary}; end
  def self.decode_plucked(column, value)
    raise ArgumentError, 'nonempty Theme SVG sprite profile unacquired'
  end
  def self.where(**conditions)
    raise ArgumentError, 'unsupported SVG sprite read predicate' unless conditions.keys == [:theme_id] && conditions[:theme_id].is_a?(Array) && conditions[:theme_id].all? { |id| id.is_a?(Integer) }
    ActiveRecord::Relation.new(self).where(conditions)
  end
end

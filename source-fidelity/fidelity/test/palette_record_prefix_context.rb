# frozen_string_literal: true
require_relative 'palette_record_prefix_source'
module PaletteRecordRead
  def self.factory_acquire; PaletteRecordPrefix.acquire; end
  def self.factory_record; PaletteRecordPrefix.record; end
  def self.factory_attributes; PaletteRecordPrefix.color_attributes; end
  def self.factory_colors; PaletteRecordPrefix.base_colors; end
  def self.acquire
    default = SiteSetting.default_theme_id
    theme = Theme.find_by(id: default)
    scheme_id = theme.nil? ? nil : theme.color_scheme_id
    selected = ColorScheme.where(remote_copy: false).find_by(id: scheme_id)
    raise 'palette selected row is not persisted' unless selected.nil? || selected.persisted?
    raise 'palette lookup admitted remote copy' unless selected.nil? || selected.remote_copy == false
    first_id = ColorScheme.where(remote_copy: false).pick(:id)
    first = first_id.nil? ? nil : ColorScheme.where(remote_copy: false).find_by(id: first_id)
    raise 'palette actual nonempty lookup changed' unless first_id.nil? || (!first.nil? && first.id == first_id && first.persisted? && first.remote_copy == false)
    factory_acquire
    record = factory_record
    attributes = factory_attributes
    fault = ENV.fetch('FIDELITY_PALETTE_PREFIX_FAULT', '')
    record.id = record.id + 1 if fault == 'wrong-id'
    record.mark_persisted! if fault == 'persisted'
    attributes[0][:hex] = 'invalid-hex' if fault == 'wrong-color' && !attributes.empty?
    raise 'palette constructor source id changed' unless record.id == PaletteRecordPrefix::NAMES_TO_ID_MAP[PaletteRecordPrefix::LIGHT_PALETTE_NAME]
    raise 'palette constructor source name changed' unless record.name == PaletteRecordPrefix::LIGHT_PALETTE_NAME
    raise 'palette constructor is not unsaved ActiveRecord' unless record.is_a?(ActiveRecord::Base) && record.new_record? && !record.persisted?
    values = factory_colors
    raise 'palette SCSS source memo identity changed' unless values.equal?(factory_colors)
    raise 'palette SCSS source is empty' if values.empty?
    raise 'palette next colors writer attributes changed' unless attributes == values.map { |name, hex| {name: name, hex: hex} }
    raise 'palette source color types changed' unless attributes.all? { |row| row.keys == [:name, :hex] && row[:name].is_a?(String) && row[:hex].is_a?(String) && row[:hex].match?(/\A(?:[0-9a-fA-F]{3}|[0-9a-fA-F]{6})\z/) }
    puts 'FIDELITY_PALETTE_RECORD_PREFIX ' + JSON.generate({default_theme: default, selected_scheme_id: scheme_id, selected_exists: !selected.nil?, actual_lookup_first_id: first_id, constructor: {id: record.id, raw_name: record.name, new_record: record.new_record?, persisted: record.persisted?}, source_colors: attributes, scss_memo_identity: true, unsaved_collection_writer_acquired: false, dynamic_i18n_name_acquired: false, source_base_flags_applied: false, stylesheet_acquired: false})
    nil
  end
end

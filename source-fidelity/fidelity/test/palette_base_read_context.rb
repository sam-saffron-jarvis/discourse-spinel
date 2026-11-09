# frozen_string_literal: true
require_relative 'palette_base_source'
module PaletteBaseRead
  def self.build_record(attrs)
    if @defaults.nil?
      rows = ActiveRecord::Base.connection.select_all("SELECT column_name,column_default,data_type FROM information_schema.columns WHERE table_schema='public' AND table_name='color_schemes' AND column_name IN ('version','via_wizard','user_selectable','remote_copy') ORDER BY ordinal_position")
      values = {}
      rows.each do |row|
        name = row['column_name']
        text = row['column_default']
        type = row['data_type']
        raise ArgumentError, 'unsupported palette schema default metadata' unless name.is_a?(String) && text.is_a?(String) && type.is_a?(String)
        if type == 'integer' && text.match?(/\A-?[0-9]+\z/)
          values[name.to_sym] = text.to_i
        elsif type == 'boolean' && ['true', 'false'].include?(text)
          values[name.to_sym] = text == 'true'
        else
          raise ArgumentError, 'unsupported palette constructor default expression'
        end
      end
      raise 'palette constructor catalog columns missing' unless values.keys.sort == [:remote_copy, :user_selectable, :version, :via_wizard]
      # The source model's actual default_scope also initializes this attribute.
      values[:remote_copy] = false
      @defaults = values
    end
    ColorScheme.new(@defaults.merge(attrs))
  end
  def self.source_base; PaletteBaseSource.base; end
  def self.acquire
    record = source_base
    raise 'base palette source object not memoized' unless record.equal?(source_base)
    raise 'base palette source not unsaved' unless record.new_record? && !record.persisted?
    fault = ENV.fetch('FIDELITY_PALETTE_BASE_FAULT', '')
    record.is_base = false if fault == 'wrong-flag'
    record.source_base_palette_name_off! if fault == 'fixed-name'
    raise 'base palette source flags changed' unless record.is_base == true && record.is_builtin_default == true
    colors = record.source_unsaved_base_colors
    colors[0].color_scheme_id = record.id if fault == 'wrong-fk'
    colors[0].mark_persisted! if fault == 'persisted-child'
    expected = PaletteRecordPrefix.base_colors.map { |name, hex| {name: name, hex: hex} }
    raise 'base palette actual colors lost or reordered' unless colors.map { |color| {name: color.name, hex: color.hex} } == expected
    raise 'base palette colors are not actual unsaved records' unless colors.all? { |color| color.is_a?(ColorSchemeColor) && color.new_record? && !color.persisted? && color.id.nil? && color.color_scheme_id.nil? && color.source_base_palette_owner.equal?(record) }
    old = I18n.locale
    names = []
    begin
      [:en, :fr].each do |locale|
        I18n.locale = locale
        name = record.name
        raise 'base palette dynamic name not String' unless name.is_a?(String)
        names << name
      end
    ensure
      I18n.locale = old
    end
    raise 'base palette I18n name did not follow locale' if names[0] == names[1]
    raise 'base palette localized name overwrote raw name' unless record.source_raw_palette_name == PaletteRecordPrefix::LIGHT_PALETTE_NAME
    other = ColorScheme.new(id: PaletteRecordPrefix::NAMES_TO_ID_MAP[PaletteRecordPrefix::LIGHT_PALETTE_NAME], name: PaletteRecordPrefix::LIGHT_PALETTE_NAME)
    raise 'base palette name override affected other record' unless other.name == PaletteRecordPrefix::LIGHT_PALETTE_NAME
    @record = {id: record.id, raw_name: record.source_raw_palette_name, version: record.version, via_wizard: record.via_wizard, user_selectable: record.user_selectable, remote_copy: record.remote_copy, names: names, new_record: record.new_record?, persisted: record.persisted?, is_base: record.is_base, is_builtin_default: record.is_builtin_default, colors: colors.map { |color| {id: color.id, name: color.name, hex: color.hex, color_scheme_id: color.color_scheme_id, new_record: color.new_record?, persisted: color.persisted?} }, memo_identity: record.equal?(source_base)}
    puts 'FIDELITY_PALETTE_BASE ' + JSON.generate(@record)
    nil
  end
end

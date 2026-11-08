# frozen_string_literal: true
# Shared diagnostic consumer, not an application settings implementation.
require "json"
require_relative "../compat/discourse/lib/site_settings/portable_core_definitions"
require_relative "../compat/discourse/lib/site_settings/portable_pg_provider"
require_relative "../compat/discourse/lib/site_settings/portable_core_readers"
require_relative "../compat/discourse/lib/site_settings/portable_scalar_readers"
require_relative "generated/portable_scalar_accessor_records"

module PortableSettingsRecords
  def self.definitions_for_comparison(definitions)
    definitions.select { |definition| definition.portable_scalar? && !definition.secret? && !definition.hidden? }
  end

  def self.read_accessors(consumer, definitions)
    records = PortableScalarAccessorRecords.read(consumer)
    raise "static accessor consumer declaration drift" unless records.map(&:first) == definitions.map(&:name)
    records
  end

  def self.read(store, definitions, site)
    definitions.map do |definition|
      value = store.get(definition.name, site)
      [definition.name, value.class.name, value]
    end
  end
end

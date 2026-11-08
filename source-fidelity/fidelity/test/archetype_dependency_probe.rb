# frozen_string_literal: true
# Original Archetype dependency lifecycle and default serialization only.
# In-memory TEST entries are unique to this short-lived process; no PG/cache.
Archetype.deregister(Archetype.default) if ENV["FIDELITY_WRONG_ARCHETYPE"] == "1"
loaded = Archetype.list.map do |item|
  { id: item.id, options: item.options, serialized: item.serializable_hash }
end
puts "FIDELITY " + JSON.generate({ kind: "original_archetypes_loaded", rows: loaded })
name = "__fidelity_archetype_dependency__"
raise "TEST name collided with original state" if Archetype.exists?(name)
options = { count: 1 }
created = Archetype.register(name, options)
raise "original registration identity" unless Archetype.list.last.equal?(created)
raise "original options alias" unless created.options.equal?(options)
options[:count] = 2
raise "runtime values frozen" unless created.options[:count] == 2
replacement = Archetype.register(name, { count: 3 })
raise "replacement did not execute" if replacement.equal?(created)
raise "replacement order changed" unless Archetype.list.last.equal?(replacement)
raise "original return identity" unless Archetype.deregister(name).equal?(replacement)
raise "deregistration did not execute" if Archetype.exists?(name)
raise "original registry was changed" unless Archetype.list.map(&:id) == loaded.map { |row| row[:id] }
puts "FIDELITY " + JSON.generate({ kind: "original_archetype_lifecycle", options_alias_value: created.options[:count], replacement_value: replacement.options[:count], absent: Archetype.exists?(name) })

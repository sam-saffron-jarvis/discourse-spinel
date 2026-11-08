# frozen_string_literal: true
# Observation ONLY. Do not write these paths back into a native program.
paths = SeedFu.fixture_paths
raise "original getter lost shared storage identity" unless paths.equal?(SeedFu.class_variable_get(:@@fixture_paths))
puts "FIDELITY " + JSON.generate({ kind: "original_seedfu_paths_observation_ONLY", paths: paths, value_class: paths.class.name, same_storage: true,
  source: SeedFu.method(:fixture_paths).source_location, autoloads: %i[VERSION Seeder ActiveRecordExtension BlockHash Runner Writer].to_h { |name| [name, SeedFu.autoload?(name)] } })

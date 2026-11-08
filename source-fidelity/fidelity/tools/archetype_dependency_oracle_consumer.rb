# frozen_string_literal: true
# Fully booted original Rails ownership checks; do not replace classes/mixins.
{
  Archetype.method(:register) => ["lib/archetype.rb", 38],
  Archetype.method(:list) => ["lib/archetype.rb", 29],
  Archetype.instance_method(:attributes) => ["lib/archetype.rb", 13],
}.each do |method, (path, line)|
  raise "actual archetype producer changed" unless method.source_location == [File.expand_path(path), line]
end
serializer_source = Archetype.instance_method(:serializable_hash).source_location
raise "real serialization mixin missing" unless serializer_source && serializer_source[0].end_with?("activemodel-8.1.4/lib/active_model/serialization.rb")
raise "serialization source changed" unless Digest::SHA256.file(serializer_source[0]).hexdigest == ENV.fetch("FIDELITY_SERIALIZATION_SHA256")

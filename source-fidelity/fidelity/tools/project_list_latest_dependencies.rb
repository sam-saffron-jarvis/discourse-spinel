# frozen_string_literal: true
# Only source-owned reads needed by the cumulative list hydration executable.
require "prism"
require "json"
require "digest"
root, output, candidate_root = ARGV
maps_path = File.join(output, "projection-map.json")
map = JSON.parse(File.read(maps_path))
candidates_path = File.join(output, "candidate-model-projections.json")
candidates = File.exist?(candidates_path) ? JSON.parse(File.read(candidates_path)) : []
specs = {
  "app/models/topic.rb" => {candidate: true, methods: %i[featured_users featured_user_ids regular? posters_summary participants_summary participant_groups_summary preload_custom_fields],
    scopes: %w[listable_topics visible secured], includes: %w[HasCustomFields Trashable],
    associations: %w[category topic_tags tags first_post image_upload topic_thumbnails], declarations: %i[attr_accessor]},
  "app/models/category.rb" => {associations: %w[parent_category]},
  "app/models/user.rb" => {methods: %i[admin?], associations: %w[primary_group flair_group uploaded_avatar]},
  "app/models/group.rb" => {associations: %w[flair_upload]},
  "app/models/post.rb" => {associations: %w[topic user], includes: %w[Trashable]},
  "app/models/upload.rb" => {associations: %w[topic_thumbnails]},
  "app/models/topic_thumbnail.rb" => {associations: %w[topic upload optimized_image]},
  "app/models/optimized_image.rb" => {associations: %w[upload]},
  "app/models/topic_custom_field.rb" => {associations: %w[topic]},
  "app/models/topic_featured_users.rb" => {methods: %i[initialize count recent_poster_count user_ids recent_user_ids slot_user_ids], declarations: %i[attr_reader], constants: %i[FREQUENT_POSTER_COUNT]},
  "app/models/topic_posters_summary.rb" => {whole: true},
  "app/models/topic_participants_summary.rb" => {whole: true},
  "app/models/topic_participant_groups_summary.rb" => {whole: true},
  "lib/user_lookup.rb" => {whole: true, candidate: true},
  "lib/group_lookup.rb" => {whole: true},
  "lib/archetype.rb" => {methods: %i[default]},
  "lib/discourse_plugin_registry.rb" => {candidate: true, methods: %i[apply_modifier topic_preloader_associations _raw_topic_preloader_associations]},
  "app/models/topic_poster.rb" => {candidate: true, methods: %i[initialize flair_group flair_group=], declarations: %i[include attr_accessor]},
}
specs.each do |path, spec|
  source = File.binread(File.join(spec[:candidate] ? candidate_root : root, path))
  parsed = Prism.parse(source)
  raise "invalid read source #{path}" unless parsed.success?
  destination = "app/models/" + File.basename(path)
  previous = spec[:candidate] ? nil : map.find { |entry| entry["generated"] == destination }
  projection = spec[:whole] ? source.dup : previous ? File.binread(File.join(output, destination)) : source.gsub(/[^\n]/, " ")
  spans = previous ? previous.fetch("selected_spans") : []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
  end
  if spec[:whole]
    spans = [{role: "whole_source_read_helper", start_byte: 0, end_byte: source.bytesize, text_sha256: Digest::SHA256.hexdigest(source)}]
  else
    owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) }
    last = source.index("\n", owner.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, owner.location.start_offset, last - owner.location.start_offset), "source_owner")
    copy.call(owner.end_keyword_loc, "source_owner_end")
    selected = []
    owner.body.body.each do |node|
      if node.is_a?(Prism::DefNode) && spec.fetch(:methods, []).include?(node.name)
        selected << node.name
        copy.call(node.location, "whole_source_read_method:#{node.name}")
      elsif node.is_a?(Prism::ConstantWriteNode) && spec.fetch(:constants, []).include?(node.name)
        copy.call(node.location, "source_constant:#{node.name}")
      elsif node.is_a?(Prism::CallNode)
        first = node.arguments&.arguments&.first
        declaration = spec.fetch(:declarations, []).include?(node.name)
        association = %i[belongs_to has_many has_one].include?(node.name) && spec.fetch(:associations, []).include?(first&.unescaped)
        scope = node.name == :scope && spec.fetch(:scopes, []).include?(first&.unescaped)
        mixin = node.name == :include && spec.fetch(:includes, []).include?(first&.slice)
        copy.call(node.location, "source_read_declaration:#{node.name}") if declaration || association || scope || mixin
      end
    end
    raise "missing read methods #{path}: #{spec[:methods] - selected}" if spec[:methods] && selected.uniq.sort != spec[:methods].sort
  end
  raise "invalid read projection #{path}" unless Prism.parse(projection).success?
  File.binwrite(File.join(output, destination), projection)
  map.reject! { |entry| entry["generated"] == destination }
  candidates.reject! { |entry| entry["generated"] == destination }
  entry = {source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "Source-owned list read/hydration roots ONLY; no lifecycle/writes or complete model API acceptance"}
  if spec[:candidate]
    entry[:source_root] = "compat/discourse"
    candidates << entry
  else
    map << entry
  end
end
File.write(maps_path, JSON.pretty_generate(map) + "\n")
File.write(candidates_path, JSON.pretty_generate(candidates) + "\n")

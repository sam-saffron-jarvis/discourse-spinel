# frozen_string_literal: true
# Bounded source-owned serializer read roots, separate candidate/original maps.
require "prism"
require "json"
require "digest"
require "fileutils"
root, output, candidate_root = ARGV
original_path = File.join(output, "projection-map.json")
candidate_path = File.join(output, "candidate-model-projections.json")
originals = JSON.parse(File.read(original_path))
candidates = JSON.parse(File.read(candidate_path))
specs = {
  "app/serializers/application_serializer.rb" => {methods: %i[_embed _root_embed attributes include? include_associations!]},
  "app/serializers/basic_user_serializer.rb" => {except_methods: %i[categories_with_notification_level category_user_notification_levels]},
  "lib/discourse_plugin_registry.rb" => {methods: %i[apply_modifier topic_preloader_associations _raw_topic_preloader_associations topic_thumbnail_sizes _raw_topic_thumbnail_sizes]},
  "lib/content_localization.rb" => {methods: %i[show_translated_topic? show_translated_tag? show_translated_category? translated_topic_fancy_title]},
  "lib/guardian.rb" => {methods: %i[initialize user authenticated? anonymous? is_admin? is_staff? is_whisperer? can_create? can_see_tags? can_tag_pms? can_lazy_load_categories? in_any_groups? can_enable_safe_mode? allow_themes?],
    declarations: %i[attr_reader attr_accessor], includes: %w[CategoryGuardian TopicGuardian],
    nested_methods: {"AnonymousUser" => %i[blank? admin? staff? secure_category_ids has_trust_level? whisperer? in_any_groups?]}},
  "lib/theme_modifier_helper.rb" => {whole: true},
  "app/models/theme.rb" => {methods: %i[parent_theme_ids components_for transform_ids lookup_modifier is_parent_theme? supported? theme_ids user_theme_ids allowed_remote_theme_ids], scopes: %w[user_selectable], associations: %w[remote_theme]},
  "app/models/theme_modifier_set.rb" => {methods: %i[modifiers resolve_modifier_for_themes load_modifiers topic_thumbnail_sizes], nested_classes: %w[ThemeModifierSetError]},
  "app/models/child_theme.rb" => {associations: %w[parent_theme child_theme]},
  "app/models/remote_theme.rb" => {},
  "app/models/tag.rb" => {methods: %i[topic_count_column topic_count_for include_tags? top_tags], associations: %w[topic_tags topics target_tag]},
  "app/models/topic.rb" => {methods: %i[featured_users featured_user_ids regular? posters_summary participants_summary participant_groups_summary preload_custom_fields private_message? image_url visible_tags nested_view? thumbnail_info],
    scopes: %w[listable_topics visible], includes: %w[HasCustomFields Trashable],
    associations: %w[category topic_tags tags first_post image_upload topic_thumbnails], declarations: %i[attr_accessor]},
  "app/models/user.rb" => {methods: %i[admin? avatar_template default_template system_avatar_template normalize_username username_hash letter_avatar_color color_index is_system_user?], associations: %w[primary_group flair_group uploaded_avatar]},
  "app/models/user_avatar.rb" => {methods: %i[local_avatar_template version]},
  "app/models/group.rb" => {methods: %i[flair_url flair_type], associations: %w[flair_upload], constants: %i[AUTO_GROUPS]},
  "app/models/optimized_image.rb" => {constants: %i[VERSION], associations: %w[upload]},
  "app/models/upload.rb" => {constants: %i[SEEDED_ID_THRESHOLD], associations: %w[topic_thumbnails]},
  "app/models/emoji.rb" => {methods: %i[gsub_emoji_to_unicode lookup_unicode replacement_code denied load_denied aliases emojis_db emojis_db_file tonable_emojis tonable_emojis_db tonable_emojis_db_file aliases_db aliases_db_file parse_emoji_file], constants: %i[FITZPATRICK_SCALE EMOJI_CODE_REGEXP]},
  "lib/pinned_check.rb" => {whole: true},
  "lib/topic_subtype.rb" => {whole: true},
}
specs.each do |path, spec|
  candidate = File.file?(File.join(candidate_root, path))
  source = File.binread(File.join(candidate ? candidate_root : root, path))
  parsed = Prism.parse(source)
  raise "invalid serializer dependency #{path}" unless parsed.success?
  owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) }
  raise "missing dependency owner #{path}" unless owner
  destination = path.start_with?("app/") ? path : "app/models/" + File.basename(path)
  prior = spec[:additive] ? originals.find { |entry| entry["generated"] == destination } : nil
  projection = spec[:whole] || spec[:except_methods] ? source.dup : prior ? File.binread(File.join(output, destination)) : source.gsub(/[^\n]/, " ")
  spans = prior ? prior["selected_spans"] : []
  copy = lambda do |location, role|
    projection[location.start_offset, location.length] = source[location.start_offset, location.length]
    spans << {role: role, start_byte: location.start_offset, end_byte: location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(source[location.start_offset, location.length])}
  end
  header = lambda do |node, role|
    ending = source.index("\n", node.location.start_offset)
    copy.call(Prism::Location.new(parsed.source, node.location.start_offset, ending - node.location.start_offset), role)
    copy.call(node.end_keyword_loc, role + "_end")
  end
  if spec[:whole]
    spans = [{role: "whole_read_source", start_byte: 0, end_byte: source.bytesize, text_sha256: Digest::SHA256.hexdigest(source)}]
  elsif spec[:except_methods]
    excluded = owner.body.body.grep(Prism::DefNode).select { |node| spec[:except_methods].include?(node.name) }
    raise "source API exclusions changed #{path}" unless excluded.length == spec[:except_methods].length
    excluded.each { |node| projection[node.location.start_offset, node.location.length] = node.slice.gsub(/[^\n]/, " ") }
    intervals = [[0, source.bytesize]]
    excluded.sort_by { |node| node.location.start_offset }.each do |node|
      intervals = intervals.flat_map do |first, last|
        next [[first, last]] unless node.location.start_offset >= first && node.location.end_offset <= last
        [[first, node.location.start_offset], [node.location.end_offset, last]]
      end
    end
    intervals.each { |first, last| copy.call(Prism::Location.new(parsed.source, first, last - first), "source_without_unrelated_notification_api") }
  else
    header.call(owner, "source_read_owner")
    selected = owner.body.body.grep(Prism::DefNode).select { |node| spec.fetch(:methods, []).include?(node.name) }
    missing = spec.fetch(:methods, []) - selected.map(&:name)
    raise "missing source read roots #{path}: #{missing}" unless missing.empty?
    selected.each { |node| copy.call(node.location, "whole_read_method:#{node.name}") }
    owner.body.body.each do |node|
      if node.is_a?(Prism::CallNode)
        first = node.arguments&.arguments&.first
        declaration = spec.fetch(:declarations, []).include?(node.name)
        association = %i[belongs_to has_many has_one].include?(node.name) && spec.fetch(:associations, []).include?(first&.unescaped)
        scope = node.name == :scope && spec.fetch(:scopes, []).include?(first&.unescaped)
        mixin = node.name == :include && spec.fetch(:includes, []).include?(first&.slice)
        copy.call(node.location, "source_read_declaration:#{node.name}") if declaration || association || scope || mixin
      elsif node.is_a?(Prism::ConstantWriteNode) && spec.fetch(:constants, []).include?(node.name)
        copy.call(node.location, "actual_source_constant:#{node.name}")
      elsif node.is_a?(Prism::ClassNode)
        if spec.fetch(:nested_classes, []).include?(node.constant_path.slice)
          copy.call(node.location, "actual_source_error_class")
        elsif names = spec.fetch(:nested_methods, {})[node.constant_path.slice]
          header.call(node, "source_identity_owner")
          methods = node.body.body.grep(Prism::DefNode).select { |method| names.include?(method.name) }
          raise "identity source methods changed" unless methods.length == names.length
          methods.each { |method| copy.call(method.location, "whole_actual_identity_method:#{method.name}") }
        end
      end
    end
  end
  raise "invalid serializer read projection #{path}" unless Prism.parse(projection).success?
  target = File.join(output, destination)
  FileUtils.mkdir_p(File.dirname(target))
  File.binwrite(target, projection)
  originals.reject! { |entry| entry["generated"] == destination }
  candidates.reject! { |entry| entry["generated"] == destination }
  entry = {source: path, generated: destination, source_sha256: Digest::SHA256.hexdigest(source),
    generated_sha256: Digest::SHA256.hexdigest(projection), selected_spans: spans,
    limitation: "Serializer read roots only, not unrelated notification/cache/write API acceptance"}
  if candidate
    entry[:source_root] = "compat/discourse"
    candidates << entry
  else
    originals << entry
  end
end
# Add the genuine original TopicList read method without changing the prior
# Stage3b component or its historical hash audit.
path = "app/models/topic_list.rb"
source = File.binread(File.join(root, path))
owner = Prism.parse(source).value.statements.body.grep(Prism::ClassNode).first
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :top_tags }
raise "original list top tag method changed" unless method
addition = "class TopicList\n  def top_tags\n    Tag.top_tags(category: @category, guardian: Guardian.new(@current_user))\n  end\nend\n"
File.write(File.join(output, "app/models/topic_list_serialization_reads.rb"), addition)
File.write(File.join(output, "serialization-list-read-addition.json"), JSON.pretty_generate({source: path,
  source_sha256: Digest::SHA256.hexdigest(source), start_byte: method.location.start_offset,
  end_byte: method.location.end_offset, text_sha256: Digest::SHA256.hexdigest(method.slice),
  generated_sha256: Digest::SHA256.hexdigest(addition), adaptation: "Same fixed keywords/default nil category, without runtime keyword splat lowered as positional Hash"}) + "\n")
File.write(original_path, JSON.pretty_generate(originals) + "\n")
File.write(candidate_path, JSON.pretty_generate(candidates) + "\n")

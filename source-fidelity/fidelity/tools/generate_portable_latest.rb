# frozen_string_literal: true
# Authorized shared application adaptations for the real latest read closure.
# Input hashes are established by generate_portable_settings.rb, not runtime rows.
def latest_nodes(node, result = [])
  result << node
  node.compact_child_nodes.each { |child| latest_nodes(child, result) }
  result
end

def generate_portable_latest(root, reference, hashes)
  transforms = []
  write_changes = lambda do |path, changes|
    source = File.binread(File.join(reference, path))
    candidate = source.dup
    changes.sort_by { |node, _| -node.location.start_offset }.each do |node, replacement|
      candidate[node.location.start_offset, node.location.length] = replacement
      transforms << {source: path, baseline_sha256: hashes.fetch(path),
        replaced_start_byte: node.location.start_offset, replaced_end_byte: node.location.end_offset,
        original_text_sha256: Digest::SHA256.hexdigest(node.slice),
        replacement_sha256: Digest::SHA256.hexdigest(replacement),
        change: "Shared latest source adaptation; full original method/metadata semantics compared separately"}
    end
    raise "invalid candidate #{path}" unless Prism.parse(candidate).success?
    target = File.join(root, "fidelity/compat/discourse", path)
    FileUtils.mkdir_p(File.dirname(target))
    File.binwrite(target, candidate)
  end

  path = "lib/discourse_plugin_registry.rb"
  source = File.binread(File.join(reference, path))
  owner = Prism.parse(source).value.statements.body.find { |node| node.is_a?(Prism::ClassNode) }
  macro = owner.body.body.find do |node|
    node.is_a?(Prism::CallNode) && node.name == :define_filtered_register &&
      node.arguments.arguments.first.slice == ":topic_preloader_associations"
  end
  raise "fixed registry declaration changed" unless macro && !macro.block
  # Expand exactly the actual fixed declaration, not a no-plugin empty result.
  # Raw storage, enabled-plugin filtering, uniq, instance shortcut, writer and
  # reset registry are the same mechanisms as define_filtered_register above.
  replacement = <<~RUBY.chomp
    @@register_names << :topic_preloader_associations

      def self._raw_topic_preloader_associations
        @topic_preloader_associations ||= Array.new
      end

      def self.topic_preloader_associations
        _raw_topic_preloader_associations.filter_map { |h| h[:value] if h[:plugin].enabled? }.uniq
      end

      def topic_preloader_associations
        self.class.topic_preloader_associations
      end

      def self.register_topic_preloader_association(value, plugin)
        _raw_topic_preloader_associations << { plugin: plugin, value: value }
      end
  RUBY
  thumbnail_macro = owner.body.body.find do |node|
    node.is_a?(Prism::CallNode) && node.name == :define_filtered_register && node.arguments.arguments.first.slice == ":topic_thumbnail_sizes"
  end
  raise "thumbnail registry declaration changed" unless thumbnail_macro && !thumbnail_macro.block
  write_changes.call(path, [[macro, replacement], [thumbnail_macro, replacement.gsub("topic_preloader_associations", "topic_thumbnail_sizes")]])

  path = "lib/user_lookup.rb"
  source = File.binread(File.join(reference, path))
  selects = latest_nodes(Prism.parse(source).value).grep(Prism::CallNode).select do |node|
    node.name == :select && %w[self.class.lookup_columns self.class.group_lookup_columns].include?(node.arguments&.arguments&.first&.slice)
  end
  raise "user/group lookup select declarations changed" unless selects.length == 2
  cache_method = latest_nodes(Prism.parse(source).value).grep(Prism::DefNode).find { |node| node.name == :set_user_group_preload }
  raise "user group cache source changed" unless cache_method
  cache_source = <<~RUBY.chomp
    def set_user_group_preload(user, group, group_association_name)
      if group_association_name == :primary_group && user.respond_to?(:_preload_primary_group)
        user._preload_primary_group(group)
      elsif group_association_name == :flair_group && user.respond_to?(:_preload_flair_group)
        user._preload_flair_group(group)
      else
        association = user.association(group_association_name)
        association.target = group
      end
    end
  RUBY
  write_changes.call(path, selects.map { |node| [node, node.slice.sub(".select(", ".select(*")] } + [[cache_method, cache_source]])

  path = "app/models/category.rb"
  source = File.binread(File.join(reference, path))
  owner = Prism.parse(source).value.statements.body.find { |node| node.is_a?(Prism::ClassNode) }
  method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :subcategory_ids && node.receiver&.slice == "self" }
  cache = method&.body&.body&.first
  raise "subcategory read source changed" unless cache.is_a?(Prism::CallNode) && cache.name == :defer_get_set && cache.block
  first = cache.block.opening_loc.end_offset
  last = cache.block.closing_loc.start_offset
  body = source[first...last]
  query = cache.block.body.body.last
  raise "subcategory SQL API changed" unless query.is_a?(Prism::CallNode) && query.name == :query_single && query.receiver.slice == "DB"
  raise "subcategory named-bind source changed" unless body.scan(":category_id").length == 1 && body.scan(":max_category_nesting").length == 1
  body = body.sub(":category_id", "?").sub(":max_category_nesting", "?")
  common_query = <<~RUBY.chomp
    ActiveRecord::Base.connection.select_rows(
            ActiveRecord::Base.sanitize_sql_array([sql, category_id, SiteSetting.max_category_nesting]),
          ).map { |row| row[0].to_i }
  RUBY
  body = body.sub(query.slice, common_query)
  replacement = "def self.subcategory_ids(category_id)" + body + "  end"
  write_changes.call(path, [[method, replacement]])
  transforms.last[:change] = "Same source recursive subcategory SELECT through common AR read adapter; fresh readonly read instead of distributed read cache"
  transforms.last[:distributed_cache_equivalence_accepted] = false

  # Expand the real inherited preloader for the statically declared core Topic.
  # Only the source model-name convention is grounded; query/order/descriptor
  # logic remains the original concern body. No field names/values are frozen.
  concern_path = "app/models/concerns/has_custom_fields.rb"
  concern_source = File.binread(File.join(reference, concern_path))
  concern = Prism.parse(concern_source).value.statements.body.find { |node| node.is_a?(Prism::ModuleNode) }
  class_api = concern.body.body.find { |node| node.is_a?(Prism::CallNode) && node.name == :class_methods }
  preloader = class_api.block.body.body.grep(Prism::DefNode).find { |node| node.name == :preload_custom_fields }
  raise "custom field preloader source changed" unless preloader
  path = "app/models/topic.rb"
  topic_source = File.binread(File.join(reference, path))
  topic = Prism.parse(topic_source).value.statements.body.find { |node| node.is_a?(Prism::ClassNode) }
  mixin = topic.body.body.find { |node| node.is_a?(Prism::CallNode) && node.name == :include && node.arguments.arguments.first.slice == "HasCustomFields" }
  raise "Topic source convention changed" unless mixin && topic.constant_path.slice == "Topic"
  preloader_source = preloader.slice.sub("def preload_custom_fields", "def self.preload_custom_fields")
  convention = '"#{name}CustomField"' + "\n          .constantize"
  raise "preloader model-name convention changed" unless preloader_source.include?(convention) && preloader_source.include?('fk = (name.underscore << "_id")')
  preloader_source = preloader_source.sub(convention, "TopicCustomField").sub('fk = (name.underscore << "_id")', 'fk = "topic_id"')
  delegate = topic.body.body.find do |node|
    node.is_a?(Prism::CallNode) && node.name == :def_delegator && node.arguments.arguments.map(&:slice) == %w[:featured_users :user_ids :featured_user_ids]
  end
  raise "featured-user delegate source changed" unless delegate
  forwarding = "def featured_user_ids(*args, &block)\n    featured_users.user_ids(*args, &block)\n  end"
  raise "preloader collection bind changed" unless preloader_source.include?('.where("name in (?)", fields)')
  preloader_source = preloader_source.sub('.where("name in (?)", fields)', '.where("name in (?)", fields.to_a)')
  json_read_bodies = {
    image_url: 'def image_url(enqueue_if_missing: false); return nil if image_upload.nil?; raise ArgumentError, "unsupported nonempty topic image serialization profile"; end',
    visible_tags: 'def visible_tags(guardian); raise ArgumentError, "unsupported nonempty visible-tag serialization profile" unless tags.empty?; tags; end',
    nested_view?: 'def nested_view?; enabled = SiteSetting.nested_replies_enabled; raise ArgumentError, "unsupported enabled nested serialization profile" if enabled; enabled; end',
    thumbnail_info: 'def thumbnail_info(enqueue_if_missing: false, extra_sizes: []); raise ArgumentError, "unsupported enabled topic thumbnail serialization profile"; end',
  }
  json_reads = topic.body.body.grep(Prism::DefNode).filter_map { |node| [node, json_read_bodies[node.name]] if json_read_bodies.key?(node.name) }
  raise "source topic serialization read roots changed" unless json_reads.length == json_read_bodies.length
  write_changes.call(path, [[mixin, mixin.slice + "\n\n  " + preloader_source], [delegate, forwarding]] + json_reads)
  transforms.last[:inherited_source] = concern_path
  transforms.last[:inherited_source_sha256] = hashes.fetch(concern_path)
  transforms.last[:inherited_method_text_sha256] = Digest::SHA256.hexdigest(preloader.slice)
  transforms.last[:change] = "Ground actual inherited preloader's core Topic name convention; read algorithm/order/field descriptors retained; explicit Set-to-array positional binding; subclasses/plugins not admitted"

  path = "lib/topics_filter.rb"
  source = File.binread(File.join(reference, path))
  owner = Prism.parse(source).value.statements.body.find { |node| node.is_a?(Prism::ClassNode) }
  mapping = owner.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :ORDER_BY_MAPPINGS }
  order = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :order_by }
  raise "order source declarations changed" unless mapping && order
  scopes = mapping.value.elements.filter_map do |association|
    key = association.key.unescaped
    scope = association.value.elements.find { |pair| pair.key.unescaped == "scope" }
    next unless scope
    raise "order scope is not the expected source lambda" unless scope.value.is_a?(Prism::LambdaNode)
    [key, scope.value]
  end
  raise "order scope set changed" unless scopes.map(&:first) == %w[category likes-op hot read]
  mapped = mapping.slice.dup
  scopes.sort_by { |_, node| -node.location.start_offset }.each do |key, node|
    start = node.location.start_offset - mapping.location.start_offset
    mapped[start, node.location.length] = ":#{key.tr('-', '_')}"
  end
  helpers = scopes.map do |key, node|
    "  def order_scope_#{key.tr('-', '_')}\n#{node.body.slice}\n  end"
  end.join("\n\n")
  dispatch = "case mapping[:scope]\n" + scopes.map do |key, _|
    "        when :#{key.tr('-', '_')}\n          @scope = order_scope_#{key.tr('-', '_')}"
  end.join("\n") + "\n        end"
  call = "@scope = instance_exec(&mapping[:scope]) if mapping[:scope]"
  raise "order dispatch source changed" unless order.slice.scan(call).length == 1
  write_changes.call(path, [[mapping, mapped + "\n\n" + helpers], [order, order.slice.sub(call, dispatch)]])
  transforms
end

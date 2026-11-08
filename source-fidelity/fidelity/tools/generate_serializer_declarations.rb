# frozen_string_literal: true
# Static expansion of pinned AMS0.8 app declarations. Executable request
# acceptance is deliberately separate; no records/observed settings are inputs.
require "prism"
require "json"
require "digest"
require "fileutils"
require "open3"
root = File.expand_path("../..", __dir__)
reference = File.join(root, "discourse")
output = File.join(root, "fidelity/compat/discourse")
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
lock_path = File.join(root, "fidelity/SOURCE_LOCK.json")
lock = JSON.parse(File.read(lock_path))
inputs = {}
read_source = lambda do |path|
  bytes, status = Open3.capture2("git", "-C", reference, "show", "#{pin}:#{path}")
  raise "missing pinned serializer source #{path}" unless status.success?
  raise "changed serializer reference #{path}" unless File.binread(File.join(reference, path)) == bytes.b
  sha = Digest::SHA256.hexdigest(bytes)
  inputs[path] = sha
  copied = File.join(root, "fidelity/source/discourse", path)
  if File.exist?(copied)
    raise "immutable serializer copy changed #{path}" unless File.binread(copied) == bytes.b
  else
    FileUtils.mkdir_p(File.dirname(copied))
    File.binwrite(copied, bytes)
  end
  prior = lock["files"].find { |entry| entry["path"] == path }
  raise "serializer lock changed #{path}" if prior && prior["sha256"] != sha
  lock["files"] << {"path" => path, "sha256" => sha} unless prior
  bytes.b
end
underscore = lambda { |name| name.gsub(/([a-z\d])([A-Z])/, '\1_\2').downcase }
infos = {}
visit = nil
visit = lambda do |name, kind = :class|
  return infos[name] if infos.key?(name)
  path = kind == :module ? "app/serializers/concerns/#{underscore.call(name)}.rb" : "app/serializers/#{underscore.call(name)}.rb"
  source = read_source.call(path)
  parsed = Prism.parse(source)
  owner = parsed.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) || node.is_a?(Prism::ModuleNode) }
  raise "serializer owner changed #{name}" unless owner&.constant_path&.slice == name
  info = {name: name, kind: kind, path: path, source: source, owner: owner, attributes: {}, associations: {}, includes: [],
    defaults: {}, methods: [], cuts: [], parent: nil}
  infos[name] = info
  if owner.is_a?(Prism::ClassNode) && owner.superclass&.slice != "ActiveModel::Serializer"
    info[:parent] = visit.call(owner.superclass.slice)
  end
  declarations = owner.body.body.grep(Prism::CallNode)
  if kind == :module
    hook = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :included && node.receiver&.slice == "self" }
    if hook
      declarations += hook.body.body
      info[:cuts] << hook
    end
  end
  declarations.each do |node|
    next unless node.is_a?(Prism::CallNode)
    args = node.arguments&.arguments || []
    case node.name
    when :attributes
      args.each do |arg|
        raise "nonliteral attribute in #{name}" unless arg.is_a?(Prism::SymbolNode)
        info[:attributes][arg.unescaped] = arg.unescaped.delete_suffix("?")
      end
      info[:cuts] << node if node.receiver.nil?
    when :has_many, :has_one
      raise "association declaration changed in #{name}" unless args.first.is_a?(Prism::SymbolNode)
      opts = {}
      args.drop(1).each do |hash|
        raise "nonliteral association metadata #{name}" unless hash.is_a?(Prism::KeywordHashNode)
        hash.elements.each do |pair|
          raise "splat association metadata #{name}" unless pair.is_a?(Prism::AssocNode)
          opts[pair.key.unescaped] = pair.value.slice
        end
      end
      info[:associations][args.first.unescaped] = {many: node.name == :has_many, options: opts}
      info[:cuts] << node
    when :include
      mixin = visit.call(args.first.slice, :module)
      info[:includes] << mixin
      info[:attributes].merge!(mixin[:attributes])
      info[:associations].merge!(mixin[:associations])
      # A fixed include in the real included callback is expanded at its
      # declaration site; the callback itself is not installed as a no-op.
    when :embed
      raise "embed mode changed #{name}" unless args.first.is_a?(Prism::SymbolNode)
      info[:defaults][:_embed] = args.first.slice
      if args[1]
        pairs = args[1].elements
        raise "embed options changed #{name}" unless pairs.length == 1 && pairs.first.key.unescaped == "include" && pairs.first.value.slice == "true"
        info[:defaults][:_root_embed] = "true"
      end
      info[:cuts] << node
    end
  end
  info[:methods] = owner.body.body.grep(Prism::DefNode).reject { |node| node.receiver }.map { |node| node.name.to_s }
  info[:methods] += owner.body.body.grep(Prism::AliasMethodNode).map { |node| node.new_name.unescaped }
  info[:associations].each_value do |association|
    serializer = association[:options]["serializer"]
    visit.call(serializer) if serializer
  end
  info
end
visit.call("TopicListSerializer")
# This graph includes real declared associations, including ones conditional at
# runtime. Method-only optional serializers are NOT silently invented here.
all_methods = nil
all_methods = lambda do |info|
  (info[:parent] ? all_methods.call(info[:parent]) : []) + info[:includes].flat_map { |mixin| all_methods.call(mixin) } + info[:methods]
end
all_attributes = lambda do |info|
  inherited = info[:parent] ? info[:parent][:all_attributes] : {}
  inherited.merge(info[:attributes])
end
# Parents are visited first but inserted before recursion; resolve explicitly.
resolve = nil
resolve = lambda do |info|
  return if info[:all_attributes]
  resolve.call(info[:parent]) if info[:parent]
  info[:all_attributes] = all_attributes.call(info)
  inherited = info[:parent] ? info[:parent][:all_associations] : {}
  info[:all_associations] = inherited.merge(info[:associations])
end
infos.each_value { |info| resolve.call(info) if info[:kind] == :class }
manifest = {profile: "WIP static AMS0.8 app declaration expansion ONLY", baseline_revision: pin, source_sha256: inputs,
  captured_payload_as_input: false, live_settings_as_inputs: false, classes: {}, candidates: {}, guarded_changes: [],
  native_query_executed: false, json_request_accepted: false, full_query_accepted: false, page_accepted: false}
infos.each_value do |info|
  source = info[:source].dup
  guarded_methods = {}
  if info[:name] == "LocalizedFancyTopicTitleMixin"
    method = info[:owner].body.body.grep(Prism::DefNode).find { |node| node.name == :include_fancy_title? }
    raise "fancy title presence source changed" unless method&.slice&.include?('_topic.present?')
    guarded_methods["include_fancy_title?"] = method.slice.sub('_topic.present?', '!_topic.nil?')
    guarded_methods["_topic"] = 'def _topic; raise ArgumentError, "unsupported non-Topic serializer object" unless object.class == Topic; @_topic ||= object; end'
  elsif info[:name] == "BasicUserSerializer"
    guarded_methods["user"] = 'def user; raise ArgumentError, "unsupported non-User basic serializer object" unless object.is_a?(User); object; end'
  elsif info[:name] == "TopicTagsMixin"
    method = info[:owner].body.body.grep(Prism::DefNode).find { |node| node.name == :tags_descriptions }
    expression = 'localized_tag_description(tag)&.truncate(DESCRIPTION_LIMIT)'
    raise "tag description source changed" unless method&.slice&.include?(expression)
    sort = info[:owner].body.body.grep(Prism::DefNode).find { |node| node.name == :all_tags }
    raise "tag sort dispatch changed" unless sort&.slice&.include?("tag.public_send(topic_count_column)")
    guarded_methods["all_tags"] = sort.slice.sub("tag.public_send(topic_count_column)", "Tag.topic_count_for(tag, scope)")
    guarded_methods["tags_descriptions"] = method.slice.sub(expression, '(description = localized_tag_description(tag); description.nil? ? nil : description.to_s.truncate(DESCRIPTION_LIMIT))')
  elsif info[:name] == "UserStatusMixin"
    guarded_methods["include_status?"] = 'def include_status?; raise ArgumentError, "unsupported status serialization profile" if @options[:include_status]; @options[:include_status]; end'
    guarded_methods["status"] = 'def status; raise ArgumentError, "unsupported status serialization profile"; end'
  elsif info[:name] == "ListableTopicSerializer"
    %w[new_posts unread_posts unread_helper].each do |name|
      guarded_methods[name] = "def #{name}; raise ArgumentError, \"unsupported authenticated unread serialization\"; end"
    end
  elsif info[:name] == "TagSerializer"
    guarded_methods["topic_count"] = "def topic_count; Tag.topic_count_for(object, scope); end"
    guarded_methods["staff"] = 'def staff; raise ArgumentError, "unsupported nonempty tag serialization profile"; end'
  elsif info[:name] == "TopicListItemSerializer"
    guarded_methods["is_hot"] = 'def is_hot; raise ArgumentError, "unsupported enabled hot-score serialization"; end'
    guarded_methods["include_is_hot?"] = 'def include_is_hot?; theme_enabled = theme_modifier_helper.serialize_topic_is_hot; plugin_enabled = DiscoursePluginRegistry.apply_modifier(:serialize_topic_is_hot, false); enabled = theme_enabled || plugin_enabled; raise ArgumentError, "unsupported enabled hot-score serialization" if enabled; enabled; end'
    %w[op_can_like op_liked].each do |name|
      guarded_methods[name] = "def #{name}; return false if !scope.user || !object.first_post; raise ArgumentError, \"unsupported authenticated OP action serialization\"; end"
    end
    guarded_methods["include_post_action?"] = 'def include_post_action?(action); raise ArgumentError, "unsupported authenticated action data" if object.user_data; object.user_data; end'
    guarded_methods["liked_post_numbers"] = 'def liked_post_numbers; raise ArgumentError, "unsupported authenticated action data"; end'
    guarded_methods["include_has_new_replies?"] = 'def include_has_new_replies?; return false unless scope.user; raise ArgumentError, "unsupported authenticated nested replies"; end'
  end
  replacements = info[:owner].body.body.grep(Prism::DefNode).filter_map do |node|
    replacement = guarded_methods[node.name.to_s]
    [node, replacement] if replacement
  end
  raise "guarded serializer source changed #{info[:name]}" unless replacements.length == guarded_methods.length
  modifications = info[:cuts].uniq.map { |node| [node, ""] } + replacements
  # Hooks may contain declarations, but only their outer span is removed.
  modifications.reject! { |node, _| modifications.any? { |outer, _| outer != node && outer.location.start_offset <= node.location.start_offset && outer.location.end_offset >= node.location.end_offset } }
  if info[:kind] == :module
    # Preserve nested include semantics of the original fixed included hook.
    inserted = info[:includes].map { |mixin| "include #{mixin[:name]}" }
  else
    methods = all_methods.call(info)
    inserted = []
    if info[:name] == "ApplicationSerializer"
      source = source.sub("class ApplicationSerializer < ActiveModel::Serializer", 'require_relative "../../lib/portable_serializer_read"' + "\n\nclass ApplicationSerializer < PortableSerializerRead")
      # Offsets below refer to the original source, so header replacement is
      # applied only after the original-coordinate declaration edits.
      source = info[:source].dup
    end
    info[:defaults].each do |name, value|
      inserted << "def self.#{name}; #{value}; end"
      # AMS class_attribute also supplies an inherited instance reader. This
      # readonly expansion follows the actual declaration in this class; no
      # runtime class mutation is admitted, and no observed value is captured.
      inserted << "def #{name}; #{value}; end"
    end
    info[:all_attributes].each do |name, _key|
      inserted << "def #{name}\n    object.#{name}\n  end" unless methods.include?(name)
    end
    (info[:all_attributes].keys + info[:all_associations].keys).uniq.each do |name|
      include_name = "include_#{name}?"
      inserted << "def #{include_name}; true; end" unless methods.include?(include_name)
    end
    attrs = info[:all_attributes].map { |name, key| "result[:#{key}] = #{name} if include?(:#{name})" }
    inserted << "def attributes\n    result = {}\n    #{attrs.join("\n    ")}\n    result\n  end"
    checks = (info[:all_attributes].keys + info[:all_associations].keys).uniq.map { |name| "when :#{name}; include_#{name}?" }
    dispatch = checks.empty? ? 'raise ArgumentError, "unknown serializer field"' : "case name\n#{checks.join("\n")}\nelse\n raise ArgumentError, \"unknown serializer field\"\nend"
    inserted << <<~RUBY
      def include?(name)
        return false if @options.key?(:only) && !Array(@options[:only]).include?(name)
        return false if @options.key?(:except) && Array(@options[:except]).include?(name)
        #{dispatch}
      end
    RUBY
    assoc_lines = []
    info[:all_associations].each do |name, association|
      opts = association[:options]
      raise "unsupported association options #{info[:name]}.#{name}: #{opts.keys}" unless (opts.keys - %w[serializer embed]).empty?
      target = opts.fetch("serializer")
      embed = opts["embed"]
      inserted << "def #{name}\n    object.#{name}\n  end" unless methods.include?(name)
      assoc_lines << "if include?(:#{name})"
      assoc_lines << "  value = #{name}"
      mode = embed ? "#{embed}" : "_embed"
      assoc_lines << "  if [:id, :ids].include?(#{mode})"
      if association[:many]
        key = name.sub(/s\z/, "") + "_ids"
        assoc_lines << "    @node[:#{key}] = value.map { |item| item.id }"
        assoc_lines << "    serializables = value.map { |item| #{target}.new(item, @options) }"
        root_key = name
      else
        assoc_lines << "    @node[:#{name}_id] = value.nil? ? nil : value.id"
        assoc_lines << "    serializables = value.nil? ? [] : [#{target}.new(value, @options)]"
        root_key = name + "s"
      end
      assoc_lines << "    if _root_embed"
      assoc_lines << "      raise ArgumentError, \"serializer root required\" if @options[:hash].nil?"
      assoc_lines << "      @options[:unique_values] ||= {}"
      assoc_lines << "      merge_association(@options[:hash], :#{root_key}, serializables, @options[:unique_values])"
      assoc_lines << "    end"
      assoc_lines << "  elsif [:object, :objects].include?(#{mode})"
      if association[:many]
        assoc_lines << "    @node[:#{name}] = value.map { |item| #{target}.new(item, @options).serializable_hash }"
      else
        assoc_lines << "    @node[:#{name}] = value.nil? ? nil : #{target}.new(value, @options).serializable_hash"
      end
      assoc_lines << "  else"
      assoc_lines << "    raise ArgumentError, \"unsupported serializer embed mode\""
      assoc_lines << "  end"
      assoc_lines << "end"
    end
    inserted << "def include_associations!\n    #{assoc_lines.join("\n    ")}\n    nil\n  end"
  end
  modifications.sort_by { |node, _| -node.location.start_offset }.each do |node, replacement|
    source[node.location.start_offset, node.location.length] = replacement
    manifest[:guarded_changes] << {source: info[:path], start_byte: node.location.start_offset, end_byte: node.location.end_offset,
      text_sha256: Digest::SHA256.hexdigest(node.slice), reason: node.is_a?(Prism::DefNode) && guarded_methods.key?(node.name.to_s) ? "Explicit supported Topic/anonymous/no-status guard; non-supported branch refuses rather than importing unrelated family" : "Fixed actual declaration/hook expanded to ordinary shared methods; no observed values or empty callback installed"}
  end
  if info[:name] == "ApplicationSerializer"
    source = source.sub("class ApplicationSerializer < ActiveModel::Serializer", 'require_relative "../../lib/portable_serializer_read"' + "\n\nclass ApplicationSerializer < PortableSerializerRead")
  end
  ending = source.rindex(/^end\s*$/)
  raise "serializer end changed #{info[:name]}" unless ending
  source.insert(ending, "\n  public\n  " + inserted.join("\n\n  ") + "\n")
  source = source.gsub(/^[ \t]+$/, "")
  raise "invalid expanded serializer #{info[:name]}" unless Prism.parse(source).success?
  destination = File.join(output, info[:path])
  FileUtils.mkdir_p(File.dirname(destination))
  File.binwrite(destination, source)
  manifest[:candidates][info[:path]] = Digest::SHA256.hexdigest(source)
  manifest[:classes][info[:name]] = {kind: info[:kind], parent: info[:parent]&.dig(:name), includes: info[:includes].map { |mixin| mixin[:name] },
    attributes: info[:all_attributes] || info[:attributes], associations: info[:all_associations] || info[:associations]}
end
File.write(lock_path, JSON.pretty_generate(lock) + "\n")
File.write(File.join(root, "fidelity/progressive/stage4/SERIALIZER_DECLARATIONS_MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate({profile: manifest[:profile], serializers: infos.keys, json_request_accepted: false})

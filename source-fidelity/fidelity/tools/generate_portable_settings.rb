#!/usr/bin/env ruby
# frozen_string_literal: true
# Build-time source declarations, NEVER an effective-settings snapshot.
require "yaml"
require "json"
require_relative "../compat/discourse/lib/site_settings/portable_read_store"
require "digest"
require "fileutils"
require "open3"
require "prism"

root = File.expand_path("../..", __dir__)
reference = File.join(root, "discourse")
candidate = File.join(root, "fidelity/compat/discourse/lib/site_settings")
pin = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
inputs = %w[app/models/site_setting.rb config/site_settings.yml lib/site_setting_extension.rb lib/site_settings/type_supervisor.rb lib/site_settings/defaults_provider.rb app/models/global_setting.rb config/discourse_defaults.conf app/models/remove_muted_tags_from_latest_site_setting.rb app/models/homepage_site_setting.rb lib/enum_site_setting.rb app/models/group.rb app/models/post_action_type.rb lib/post_action_type_view.rb lib/topic_query.rb app/models/topic_list.rb lib/discourse.rb app/models/category_user.rb app/models/topic_user.rb app/models/dismissed_topic_user.rb app/models/post_action.rb lib/search.rb app/models/topic_poster.rb lib/discourse_plugin_registry.rb lib/topics_filter.rb app/models/category.rb app/models/concerns/has_custom_fields.rb app/models/topic.rb lib/user_lookup.rb]
hashes = inputs.to_h do |path|
  bytes, status = Open3.capture2("git", "-C", reference, "show", "#{pin}:#{path}")
  raise "cannot read pinned #{path}" unless status.success?
  raise "reference changed: #{path}" unless File.binread(File.join(reference, path)) == bytes.b
  [path, Digest::SHA256.hexdigest(bytes)]
end
# UNIT-only namespace for exercising the generated permission-map transform.
# Copy the real constant byte-for-byte; this is not a Group/Guardian substitute
# or a production/native bootstrap input.
group_source = File.read(File.join(reference, "app/models/group.rb"))
group_tree = Prism.parse(group_source)
group_class = group_tree.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "Group" }
group_ids = group_class.body.body.find { |node| node.is_a?(Prism::ConstantWriteNode) && node.name == :AUTO_GROUPS }
raise "group source constant missing" unless group_ids
fixture_path = File.join(root, "fidelity/test/generated/portable_group_ids_fixture.rb")
FileUtils.mkdir_p(File.dirname(fixture_path))
fixture = "# frozen_string_literal: true\n# GENERATED UNIT-only real source constant; NOT Group model/security implementation.\nclass Group\n  #{group_ids.slice}\nend\n"
File.write(fixture_path, fixture)

types_source = File.read(File.join(reference, "lib/site_settings/type_supervisor.rb"))
type_body = types_source.match(/Enum\.new\((.*?)\n\s*\)/m) or raise "type declaration not found"
types = type_body[1].scan(/(\w+):\s*(\d+)/).to_h.transform_values(&:to_i)
# PortableReadStore's wire codec is this original source contract.
raise "source type ABI changed" unless types.values == (1..33).to_a &&
  types.values_at("string", "integer", "float", "bool", "null", "enum", "file_size_restriction", "datetime", "icon", "date") == [1, 3, 4, 5, 6, 7, 27, 31, 32, 33]

# The actual core query needs this enum, whose complete pinned class only
# defines constants/validation/choices and never calls wrap_values!. Do not
# infer that all enums are raw: DuplicateTopicTitlesSiteSetting really wraps.
enum_source = File.read(File.join(reference, "app/models/remove_muted_tags_from_latest_site_setting.rb"))
enum_tree = Prism.parse(enum_source)
raise "enum parse failed" unless enum_tree.success?
enum_class = enum_tree.value.statements.body.fetch(0)
raise "unwrapped enum ownership changed" unless enum_class.is_a?(Prism::ClassNode) &&
  enum_class.constant_path.slice == "RemoveMutedTagsFromLatestSiteSetting" && enum_class.superclass.slice == "EnumSiteSetting"
raise "unwrapped enum gained activation code" unless enum_class.body.body.all? do |node|
  node.is_a?(Prism::ConstantWriteNode) || (node.is_a?(Prism::DefNode) &&
    node.receiver&.slice == "self" && %i[valid_value? values translate_names?].include?(node.name))
end

# HTML metadata needs the actual unwrapped Homepage enum. Only method bodies and
# the private visibility declaration occur in this pinned class; no wrap_values!
# activation or wrap method exists. Read-time conversion is TypeSupervisor's
# default-String enum conversion, not its separate choices/validation protocol.
homepage_enum = Prism.parse_file(File.join(reference, "app/models/homepage_site_setting.rb"))
homepage_class = homepage_enum.value.statements.body.grep(Prism::ClassNode).fetch(0)
raise "homepage enum owner changed" unless homepage_class.constant_path.slice == "HomepageSiteSetting" && homepage_class.superclass.slice == "EnumSiteSetting"
raise "homepage enum gained wrapping/activation" unless homepage_class.body.body.all? do |node|
  (node.is_a?(Prism::DefNode) && node.receiver&.slice == "self" && %i[valid_value? values choices translate_names? offered?].include?(node.name)) ||
    (node.is_a?(Prism::CallNode) && node.name == :private_class_method && node.arguments.arguments.first.slice == ":offered?")
end

rows = []
custom_source_getters = File.read(File.join(reference, "app/models/site_setting.rb")).scan(/def self\.(\w+)/).flatten
YAML.load_file(File.join(reference, "config/site_settings.yml"), aliases: true).each do |category, settings|
  settings.each do |name, declaration|
    if declaration.is_a?(Hash)
      options = declaration.dup
      default = options.delete("default")
      raise "missing default: #{name}" if default.nil?
    else
      default = declaration
      options = {}
    end
    options["category"] = category
    if (name == "remove_muted_tags_from_latest" && options["enum"] == "RemoveMutedTagsFromLatestSiteSetting") ||
       (name == "default_homepage" && options["enum"] == "HomepageSiteSetting")
      options["portable_unwrapped_enum"] = true
    end
    options["portable_source_override"] = true if custom_source_getters.include?(name)
    type = types[options["type"]]
    type ||= case default
    when String then types.fetch("string")
    when Integer then types.fetch("integer")
    when Float then types.fetch("float")
    when TrueClass, FalseClass then types.fetch("bool")
    when NilClass then types.fetch("null")
    else raise "untyped declaration: #{name}"
    end
    raise "invalid source method name #{name}" unless /\A[a-z][a-z0-9_]*\z/.match?(name)
    rows << [name, default, type, options]
  end
end
# This API/default comes from SiteSettingExtension#default_locale and
# DefaultsProvider::DEFAULT_LOCALE, not from a captured site's locale.
raise "locale source contract changed" unless File.read(File.join(reference, "lib/site_settings/defaults_provider.rb")).include?('DEFAULT_LOCALE = "en"')
rows.unshift(["default_locale", "en", types.fetch("string"), {"client" => true, "category" => "required"}])
raise "duplicate source setting" unless rows.map(&:first).uniq.length == rows.length

FileUtils.mkdir_p(candidate)
header = "# frozen_string_literal: true\n# GENERATED by fidelity/tools/generate_portable_settings.rb from pinned declarations.\n# No effective settings, DB values or observed runtime types are inputs.\n"
source = +header
source << "require_relative \"portable_read_store\"\nmodule SiteSettings\n  class PortableCoreDefinitions\n    def self.build\n      definitions = []\n"
rows.each_slice(96).with_index { |_, index| source << "      definitions.concat(part_#{index})\n" }
source << "      definitions\n    end\n"
rows.each_slice(96).with_index do |slice, index|
  source << "    def self.part_#{index}\n      definitions = []\n"
  slice.each do |name, default, type, options|
    source << "      definitions << PortableDefinition.new(#{name.dump}, #{default.inspect}, #{type}, #{JSON.generate(options).dump})\n"
  end
  source << "      definitions\n    end\n"
end
source << "  end\nend\n"
File.write(File.join(candidate, "portable_core_definitions.rb"), source)

readers = +header
readers << "# Include/extend in the candidate facade; portable_store/portable_site are its runtime context.\nmodule SiteSettings\n  module PortableCoreReaders\n"
rows.each do |name, _, type, options|
  readers << "    def #{name}(scoped_to = nil)\n      portable_store.get(#{name.dump}, portable_site)\n    end\n"
  readers << "    def #{name}?(scoped_to = nil)\n"
  readers << (name == "default_locale" ? "      true\n" : "      #{name}(scoped_to)\n")
  readers << "    end\n    def #{name}=(value)\n      portable_store.set(#{name.dump}, value, portable_site)\n    end\n"
  if %w[category_list group_list].include?(options["type"])
    readers << "    def #{name}_map\n"
    if options["type"] == "group_list"
      readers << "      raise PortableUnsupported, \"group security map #{name} needs its source upcoming-change contract\"\n"
    else
      readers << "      #{name}.to_s.split(\"|\").map(&:to_i)\n"
    end
    readers << "    end\n"
  elsif %w[list emoji_list tag_list host_list].include?(options["type"]) &&
      (options["list_type"].nil? || %w[simple compact locale].include?(options["list_type"]))
    readers << "    def #{name}_map(scoped_to = nil)\n      #{name}(scoped_to).to_s.split(\"|\")\n    end\n"
  end
end
readers << "  end\nend\n"
File.write(File.join(candidate, "portable_core_readers.rb"), readers)
# Rails hybrid integration retains all original special-setting accessors,
# deprecated wrappers and the special default_locale API. Only statically
# supported scalar accessors replace runtime method generation.
scalar_readers = +header
scalar_readers << "module SiteSettings\n  module PortableScalarReaders\n"
rows.each do |name, default, type, options|
  definition = SiteSettings::PortableDefinition.new(name, default, type, JSON.generate(options))
  next unless definition.portable_scalar? && name != "default_locale"
  scalar_readers << "    def #{name}(scoped_to = nil)\n      portable_store.get(#{name.dump}, portable_site)\n    end\n"
  scalar_readers << "    def #{name}?(scoped_to = nil)\n      #{name}(scoped_to)\n    end\n"
  scalar_readers << "    def #{name}=(value)\n      portable_store.set(#{name.dump}, value, portable_site)\n    end\n"
  if options["type"] == "group_list"
    scalar_readers << "    def #{name}_map\n      ids = #{name}.to_s.split(\"|\").map(&:to_i)\n      if ids.include?(Group::AUTO_GROUPS[:everyone]) && granular_anonymous_and_logged_in_groups_permissions\n        ids = ids.map { |id| id == Group::AUTO_GROUPS[:everyone] ? Group::AUTO_GROUPS[:logged_in_users] : id }.uniq\n      end\n      ids\n    end\n"
  elsif options["type"] == "category_list"
    scalar_readers << "    def #{name}_map\n      #{name}.to_s.split(\"|\").map(&:to_i)\n    end\n"
  elsif %w[list emoji_list tag_list host_list].include?(options["type"]) &&
      (options["list_type"].nil? || %w[simple compact locale].include?(options["list_type"]))
    scalar_readers << "    def #{name}_map(scoped_to = nil)\n      #{name}(scoped_to).to_s.split(\"|\")\n    end\n"
  end
end
scalar_readers << "  end\nend\n"
File.write(File.join(candidate, "portable_scalar_readers.rb"), scalar_readers)

# Public interface for the separately compiled, already-native-tested mixin.
# Do NOT infer return types from an observed site or even just YAML defaults:
# live global configuration can shadow a bool/string with another primitive.
# This conservative union preserves those actual API possibilities. The native
# bootstrap MUST install the real module; the signature supplies no body/value.
scalar_rbs = +"# GENERATED source-declared native mixin interface; no value/type snapshot.\nclass SiteSetting\n"
rows.each do |name, default, type, options|
  definition = SiteSettings::PortableDefinition.new(name, default, type, JSON.generate(options))
  next unless definition.portable_scalar? && name != "default_locale"
  scalar_rbs << "  def self.#{name}: () -> (String | Integer | Float | bool | nil)\n"
  scalar_rbs << "  def self.#{name}?: () -> (String | Integer | Float | bool | nil)\n"
end
scalar_rbs << "end\n"
scalar_rbs_path = File.join(root, "fidelity/compat/discourse/sig/portable_scalar_readers.rbs")
FileUtils.mkdir_p(File.dirname(scalar_rbs_path))
File.write(scalar_rbs_path, scalar_rbs)

# TEST-only static invocation list: Spinel deliberately rejects public_send
# with a runtime name. Names/selection derive from declarations, not observed
# values. This is a consumer of the COMPLETE application accessor module.
record_consumer = +header
record_consumer << "# UNIT/live comparison consumer ONLY, never application settings data.\nmodule PortableScalarAccessorRecords\n  def self.read(consumer)\n    records = []\n"
rows.each do |name, default, type, options|
  definition = SiteSettings::PortableDefinition.new(name, default, type, JSON.generate(options))
  next unless definition.portable_scalar? && !definition.secret? && !definition.hidden?
  record_consumer << "    value = consumer.#{name}\n    records << [#{name.dump}, value.class.name, value]\n"
end
record_consumer << "    records\n  end\nend\n"
record_consumer_path = File.join(root, "fidelity/test/generated/portable_scalar_accessor_records.rb")
File.write(record_consumer_path, record_consumer)

# Full candidate file: the reference remains untouched. Only application
# extension wiring is changed; every original model helper/callback remains.
model = File.read(File.join(reference, "app/models/site_setting.rb"))
model = model.sub("class SiteSetting < ActiveRecord::Base", "require_relative \"../../lib/site_settings/portable_rails_extension\"\n\nclass SiteSetting < ActiveRecord::Base")
model = model.sub("  extend SiteSettingExtension", "  extend SiteSettingExtension\n  extend SiteSettings::PortableSettingsContext\n  extend SiteSettings::PortableRailsExtension\n  extend SiteSettings::PortableScalarReaders")
model_path = File.join(root, "fidelity/compat/discourse/app/models/site_setting.rb")
FileUtils.mkdir_p(File.dirname(model_path))
File.write(model_path, model)

# The measured latest closure also reaches PostActionType.types. Its pinned
# source synthesizes a fixed list of forwarding methods at runtime. Spell the
# SAME names/calls/rest-argument contract explicitly in shared application code.
post_action_source = File.binread(File.join(reference, "app/models/post_action_type.rb"))
post_action_tree = Prism.parse(post_action_source)
post_action_owner = post_action_tree.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "PostActionType" }
post_action_singleton = post_action_owner.body.body.find { |node| node.is_a?(Prism::SingletonClassNode) }
forwarder_macro = post_action_singleton.body.body.find do |node|
  node.is_a?(Prism::CallNode) && node.name == :each && node.receiver.is_a?(Prism::ArrayNode) &&
    node.block&.body&.slice&.include?("PostActionTypeView.new.send(method_name, *args)")
end
raise "original fixed post-action forwarder contract changed" unless forwarder_macro
forwarder_names = forwarder_macro.receiver.elements.map(&:unescaped)
raise "invalid fixed delegate" unless forwarder_names.all? { |name| /\A[a-z_]+\??\z/.match?(name) }
forwarders = forwarder_names.map do |name|
  "def #{name}(*args)\n      PostActionTypeView.new.#{name}(*args)\n    end"
end.join("\n\n    ")
post_action_candidate = post_action_source.dup
post_action_candidate[forwarder_macro.location.start_offset, forwarder_macro.location.length] = forwarders
File.write(File.join(root, "fidelity/compat/discourse/app/models/post_action_type.rb"), post_action_candidate)

# Preserve the actual fixed mattr_accessor :redis API without macro/reflection
# protocol assumptions. The four public methods/class-variable initialization
# match ActiveSupport's source contract, including preserving a prior value.
discourse_source = File.binread(File.join(reference, "lib/discourse.rb"))
discourse_tree = Prism.parse(discourse_source)
discourse_owner = discourse_tree.value.statements.body.find { |node| node.is_a?(Prism::ModuleNode) && node.constant_path.slice == "Discourse" }
redis_macro = discourse_owner.body.body.find do |node|
  node.is_a?(Prism::CallNode) && node.name == :mattr_accessor && node.arguments&.arguments&.map(&:slice) == [":redis"]
end
raise "original redis accessor declaration changed" unless redis_macro
redis_accessors = <<~RUBY.chomp
  @@redis = nil unless defined?(@@redis)

    def self.redis
      @@redis
    end

    def self.redis=(val)
      @@redis = val
    end

    def redis
      @@redis
    end

    def redis=(val)
      @@redis = val
    end
RUBY
discourse_candidate = discourse_source.dup
discourse_candidate[redis_macro.location.start_offset, redis_macro.location.length] = redis_accessors
File.write(File.join(root, "fidelity/compat/discourse/lib/discourse.rb"), discourse_candidate)

# Read-only core milestone: keep flag metadata queries/enum/visibility logic,
# but read directly rather than route this read view through a distributed
# Marshal cache. Instance memoization remains; normal model invalidation hooks
# are not removed. Distributed flag-read cache equivalence is NOT claimed.
flag_view_source = File.binread(File.join(reference, "lib/post_action_type_view.rb"))
flag_view_tree = Prism.parse(flag_view_source)
flag_view_owner = flag_view_tree.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "PostActionTypeView" }
flag_view_replacements = {
  all_flags: "def all_flags\n    @all_flags ||= Flag.unscoped.order(:position).pluck(ATTRIBUTE_NAMES).map { |attributes| ATTRIBUTE_NAMES.zip(attributes).to_h }\n  end",
  public_type_ids: "def public_type_ids\n    public_types.values\n  end",
}
flag_view_transforms = []
flag_view_candidate = flag_view_source.dup
flag_view_replacements.map do |name, replacement|
  node = flag_view_owner.body.body.find { |item| item.is_a?(Prism::DefNode) && item.name == name }
  raise "flag view method changed: #{name}" unless node
  flag_view_transforms << { source: "lib/post_action_type_view.rb", baseline_sha256: hashes.fetch("lib/post_action_type_view.rb"),
    replaced_start_byte: node.location.start_offset, replaced_end_byte: node.location.end_offset,
    original_text_sha256: Digest::SHA256.hexdigest(node.slice), replacement_sha256: Digest::SHA256.hexdigest(replacement),
    change: "Shared readonly flag metadata query; instance memoization retained; distributed read-cache equivalence NOT claimed", method: name }
  [node, replacement]
end.sort_by { |node, _| -node.location.start_offset }.each do |node, replacement|
  flag_view_candidate[node.location.start_offset, node.location.length] = replacement
end
File.write(File.join(root, "fidelity/compat/discourse/lib/post_action_type_view.rb"), flag_view_candidate)

# Make the existing anonymous early return explicit before the general Rails
# blank? predicate. This preserves nil/false/empty handling and all query bodies,
# while exposing the nonnil branch to both runtimes without a compiler feature.
nil_guard_transforms = []
%w[category_user topic_user dismissed_topic_user].each do |basename|
  path = "app/models/#{basename}.rb"
  original = File.binread(File.join(reference, path))
  # The scoped source function has precisely this leading guard; no unrelated
  # user.blank? sites or authorization decisions are rewritten.
  pattern = /def (?:self\.)?lookup_for\(user, (?:category_ids|topics)\).*?return (?:\{\}|\[\]) if user\.blank\?/m
  match = pattern.match(original) or raise "lookup_for anonymous guard changed: #{path}"
  start = match.end(0) - "user.blank?".bytesize
  replacement = "user.nil? || user.blank?"
  changed = original.dup
  changed[start, "user.blank?".bytesize] = replacement
  File.write(File.join(root, "fidelity/compat/discourse", path), changed)
  nil_guard_transforms << {source: path, baseline_sha256: hashes.fetch(path), replaced_start_byte: start,
    replaced_end_byte: start + "user.blank?".bytesize, original_text_sha256: Digest::SHA256.hexdigest("user.blank?"),
    replacement_sha256: Digest::SHA256.hexdigest(replacement),
    change: "Existing anonymous early return made explicit; blank? and complete query bodies retained"}
end

# Preserve PostAction.lookup_for's original joined/deleted/user/type/topic/order
# query using the common AR read API rather than a MiniSql-specific builder.
# This is the same application lookup, NOT a replacement topic backend.
post_action_lookup_source = File.binread(File.join(reference, "app/models/post_action.rb"))
post_action_lookup_tree = Prism.parse(post_action_lookup_source)
post_action_lookup_owner = post_action_lookup_tree.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "PostAction" }
post_action_lookup = post_action_lookup_owner.body.body.find { |node| node.is_a?(Prism::DefNode) && node.name == :lookup_for && node.receiver&.slice == "self" }
raise "PostAction lookup source changed" unless post_action_lookup
portable_post_action_lookup = <<~RUBY.chomp
  def self.lookup_for(user, topics, post_action_type_id)
      return if topics.blank?
      topic_ids = topics.map(&:id)
      map = {}
      rows =
        PostAction.unscoped
          .joins("INNER JOIN posts ON posts.id = post_actions.post_id")
          .where("posts.deleted_at IS NULL AND post_actions.deleted_at IS NULL")
          .where(post_action_type_id: post_action_type_id, user_id: user.id)
          .where(posts: { topic_id: topic_ids })
          .order("posts.topic_id, posts.post_number")
          .pluck("posts.topic_id", "posts.post_number")
      rows.each { |topic_id, post_number| (map[topic_id] ||= []) << post_number }
      map
    end
RUBY
post_action_lookup_candidate = post_action_lookup_source.dup
post_action_lookup_candidate[post_action_lookup.location.start_offset, post_action_lookup.location.length] = portable_post_action_lookup
File.write(File.join(root, "fidelity/compat/discourse/app/models/post_action.rb"), post_action_lookup_candidate)
post_action_lookup_transform = {source: "app/models/post_action.rb", baseline_sha256: hashes.fetch("app/models/post_action.rb"),
  replaced_start_byte: post_action_lookup.location.start_offset, replaced_end_byte: post_action_lookup.location.end_offset,
  original_text_sha256: Digest::SHA256.hexdigest(post_action_lookup.slice), replacement_sha256: Digest::SHA256.hexdigest(portable_post_action_lookup),
  change: "Same readonly post-action lookup joins/predicates/order via common AR API instead of MiniSql row builder"}

# Reuse the common adapter for these two real search SQL seams. Preserve the
# original search-specific backslash pass as source text, rather than silently
# changing query escaping while removing the PG::Connection constant dependency.
search_source = File.binread(File.join(reference, "lib/search.rb"))
search_tree = Prism.parse(search_source)
search_owner = search_tree.value.statements.body.find { |node| node.is_a?(Prism::ClassNode) && node.constant_path.slice == "Search" }
search_escape = search_owner.body.body.find { |node| node.is_a?(Prism::DefNode) && node.name == :escape_string && node.receiver&.slice == "self" }
search_unaccent = search_owner.body.body.find { |node| node.is_a?(Prism::DefNode) && node.name == :unaccent && node.receiver&.slice == "self" }
raise "search SQL source contract changed" unless search_escape && search_unaccent
original_escape_expression = search_escape.body.body.fetch(0).slice
pg_escape = "PG::Connection.escape_string(term)"
raise "search PG escape source changed" unless original_escape_expression.start_with?(pg_escape)
escape_suffix = original_escape_expression.delete_prefix(pg_escape)
raise "search escape suffix changed" unless escape_suffix.start_with?(".gsub(")
search_replacements = {
  search_unaccent => "def self.unaccent(str)\n    if SiteSetting.search_ignore_accents\n      sql = ActiveRecord::Base.sanitize_sql_array([\"SELECT unaccent(?)\", str])\n      ActiveRecord::Base.connection.select_value(sql)\n    else\n      str\n    end\n  end",
  search_escape => "def self.escape_string(term)\n    quoted = ActiveRecord::Base.connection.quote_string(term)\n    raise ArgumentError, \"string contains null byte\" if quoted.include?(\"\\0\")\n    quoted#{escape_suffix}\n  end",
}
search_transforms = []
search_candidate = search_source.dup
search_replacements.sort_by { |node, _| -node.location.start_offset }.each do |node, replacement|
  search_candidate[node.location.start_offset, node.location.length] = replacement
  search_transforms << {source: "lib/search.rb", baseline_sha256: hashes.fetch("lib/search.rb"),
    replaced_start_byte: node.location.start_offset, replaced_end_byte: node.location.end_offset,
    original_text_sha256: Digest::SHA256.hexdigest(node.slice), replacement_sha256: Digest::SHA256.hexdigest(replacement),
    change: "Same search SQL/unaccent/escaping via common AR adapter instead of MiniSql/static PG namespace", method: node.name}
end
File.write(File.join(root, "fidelity/compat/discourse/lib/search.rb"), search_candidate)

# Native compile measured the actual unsupported OpenStruct inheritance.
# Retain the app's ordinary declared ivar accessors/serialization, and compose
# the actual OpenStruct for its table/flair_group API instead of subclassing it.
poster_source = File.binread(File.join(reference, "app/models/topic_poster.rb"))
poster_candidate = poster_source.sub("class TopicPoster < OpenStruct", "require \"ostruct\"\n\nclass TopicPoster")
poster_anchor = "  attr_accessor :user, :description, :extras, :id, :primary_group"
raise "TopicPoster source accessors changed" unless poster_candidate.include?(poster_anchor)
poster_composition = <<~RUBY.chomp
    def initialize(hash = nil)
      @data = OpenStruct.new(hash)
    end

    def flair_group
      @data[:flair_group]
    end

    def flair_group=(x)
      @data[:flair_group] = x
    end

    def [](name)
      @data[name]
    end

    def []=(name, value)
      @data[name] = value
    end

    def to_h(&block)
      @data.to_h.to_h(&block)
    end

    def each_pair
      return enum_for(:each_pair) unless block_given?
      @data.each_pair { |pair| yield pair }
      self
    end

    def dig(name, *names)
      @data.dig(name, *names)
    end

    def delete_field(name, &block)
      @data.delete_field(name, &block)
    end

    def freeze
      @data.freeze
      super
    end

    private def initialize_dup(orig)
      super
      @data = @data.dup
    end

    private def initialize_clone(orig)
      super
      @data = @data.clone
    end

    def respond_to?(name, include_private = false)
      if name.to_sym == :flair_group || name.to_sym == :flair_group=
        @data.respond_to?(name, include_private)
      else
        super
      end
    end

    private def respond_to_missing?(name, include_private = false)
      @data.respond_to?(name, include_private) || super
    end

    private def method_missing(name, *args)
      text = name.to_s
      if text.end_with?("=")
        if args.length != 1
          raise ArgumentError, "wrong number of arguments (given \#{args.length}, expected 1)"
        end
        self[text[0...-1]] = args[0]
      elsif args.empty?
        self[name]
      else
        super
      end
    end
RUBY
poster_candidate = poster_candidate.sub(poster_anchor, poster_anchor + "\n\n" + poster_composition.lines.map { |line| "  " + line }.join)
File.write(File.join(root, "fidelity/compat/discourse/app/models/topic_poster.rb"), poster_candidate)
poster_transform = {source: "app/models/topic_poster.rb", baseline_sha256: hashes.fetch("app/models/topic_poster.rb"),
  change: "Compose actual OpenStruct instead of unsupported native subclass; preserve declared fields, constructor/key contracts, block/enumeration and dynamic-field APIs",
  supported_scope: "CRuby differential: constructor/declared fields/flair/key APIs, parameter and error descriptors, block to_h, each_pair, dig/delete, copies/freeze; native app fields still require end-to-end execution",
  unproved_scope: "nominal OpenStruct ancestry, inherited aliases/reflection/equality/collision APIs, and native dynamic method_missing dispatch outside statically declared app fields"}

require_relative "generate_portable_latest"
latest_transforms = generate_portable_latest(root, reference, hashes)

outputs = Dir.glob(File.join(root, "fidelity/compat/discourse/**/*.{rb,rbs,json,woff2}")).sort.to_h do |path|
  [path.delete_prefix(File.join(root, "fidelity/compat/")), Digest::SHA256.file(path).hexdigest]
end
supplementary_manifests = Dir.glob(File.join(root, "fidelity/progressive/stage{4,4_request}/*MANIFEST.json")).sort.to_h do |path|
  [path.delete_prefix(File.join(root, "fidelity/")), Digest::SHA256.file(path).hexdigest]
end
manifest = {
  profile: "patched-core-no-plugins-shared-settings", baseline_revision: pin,
  supplementary_source_manifests: supplementary_manifests,
  reference_source_sha256: hashes, candidate_source_sha256: outputs,
  unit_only_fixtures: { "test/generated/portable_group_ids_fixture.rb" => {
    source: "app/models/group.rb", source_sha256: hashes.fetch("app/models/group.rb"),
    start_byte: group_ids.location.start_offset, end_byte: group_ids.location.end_offset,
    selected_text_sha256: Digest::SHA256.hexdigest(group_ids.slice),
    generated_sha256: Digest::SHA256.hexdigest(fixture), production_input: false,
  } },
  generated_test_consumer: { path: "test/generated/portable_scalar_accessor_records.rb",
    sha256: Digest::SHA256.hexdigest(record_consumer), production_input: false,
    invocation_names_from_source_declarations_only: true },
  generated_definitions: rows.length, generated_accessors_from_source_only: true,
  observed_values_or_effective_snapshot_as_inputs: false,
  changes: ["New shared portable read-store and readonly PG provider", "Core declaration/accessor generation replaces runtime name synthesis at this boundary", "Full candidate SiteSetting model wires shared scalar readers/cache while preserving original special-setting metadata/helpers/callbacks"],
  source_transforms: [{ source: "app/models/post_action_type.rb", baseline_sha256: hashes.fetch("app/models/post_action_type.rb"),
    replaced_start_byte: forwarder_macro.location.start_offset, replaced_end_byte: forwarder_macro.location.end_offset,
    original_text_sha256: Digest::SHA256.hexdigest(forwarder_macro.slice),
    change: "Fixed dynamic define_method forwarding list expanded to explicit methods with identical rest arguments/target names",
    delegated_names: forwarder_names },
    { source: "lib/discourse.rb", baseline_sha256: hashes.fetch("lib/discourse.rb"),
      replaced_start_byte: redis_macro.location.start_offset, replaced_end_byte: redis_macro.location.end_offset,
      original_text_sha256: Digest::SHA256.hexdigest(redis_macro.slice),
      change: "Fixed redis mattr macro expanded to real shared class-variable module/instance readers/writers; prior value preserved",
      replacement_sha256: Digest::SHA256.hexdigest(redis_accessors) }] + flag_view_transforms + nil_guard_transforms + [post_action_lookup_transform] + search_transforms + [poster_transform] + latest_transforms,
  integration: "Hybrid Rails adapter: shared scalar cache/static accessors; original special-setting implementations retained",
  not_yet_integrated: ["native full SiteSetting facade/bootstrap", "theme/upload/object/enum-wrapper special getters", "upcoming changes and group security maps", "change bus/cache invalidation integration", "settings writes/plugins", "query/security/serializer/controller/document/browser"],
  native_proof: false, full_site_setting_api_accepted: false, core_latest_accepted: false,
}
File.write(File.join(root, "fidelity/compat/MANIFEST.json"), JSON.pretty_generate(manifest) + "\n")
puts JSON.generate({profile: manifest[:profile], declarations: rows.length, effective_values_captured: false})

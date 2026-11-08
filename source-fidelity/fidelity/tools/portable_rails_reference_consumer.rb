# frozen_string_literal: true
# TEST-only consumer: real boot, real getters/security/client serializers/query.
load File.join(__dir__, "core_no_plugins_reference_consumer.rb")
if SiteSetting.respond_to?(:portable_definitions)
  definitions = SiteSetting.portable_definitions
else
  require_relative "../compat/discourse/lib/site_settings/portable_core_definitions"
  definitions = SiteSettings::PortableCoreDefinitions.build
end

records = []
def portable_record_value(value)
  case value
  when Upload
    # Respect Discourse's prohibition on unrestricted AR serialization.
    { "id" => value.id, "url" => value.url }
  when Array
    value.map { |item| portable_record_value(item) }
  when Hash
    value.transform_values { |item| portable_record_value(item) }
  else
    JSON.parse(value.to_json)
  end
end

def capture_portable_setting(records, label)
  value = yield
  records << [label, "value", value.class.name, portable_record_value(value)]
rescue SiteSettingExtension::InvalidSettingAccess, ArgumentError, Discourse::InvalidParameters => error
  records << [label, "error", error.class.name, error.message]
end

definitions.each do |definition|
  next if definition.secret?
  name = definition.name
  capture_portable_setting(records, name) { SiteSetting.public_send(name) }
  capture_portable_setting(records, "#{name}?") { SiteSetting.public_send("#{name}?") }
  # Non-theme getters accept/ignore a supplied scope; theme getters must enforce
  # it and use their actual theme contract rather than a nil/default shortcut.
  capture_portable_setting(records, "#{name}[scope]") do
    SiteSetting.public_send(name, { theme_id: -1 })
  end
  map_name = "#{name}_map"
  capture_portable_setting(records, map_name) { SiteSetting.public_send(map_name) } if SiteSetting.respond_to?(map_name)
  groups_name = "#{name}_groups_map"
  capture_portable_setting(records, groups_name) { SiteSetting.public_send(groups_name) } if SiteSetting.respond_to?(groups_name)
end
# Read real public flag metadata through the original/candidate forwarders.
# These are live DB/cache-backed values, never production fixture inputs.
%i[types public_types public_type_ids flag_types notify_flag_type_ids topic_flag_types names descriptions applies_to].each do |name|
  capture_portable_setting(records, "PostActionType.#{name}") { PostActionType.public_send(name) }
  method = PostActionType.method(name)
  records << ["PostActionType.#{name}[descriptor]", "value", "Array", [method.arity, method.parameters]]
end
# Exercise the actual module/instance redis accessor contract without issuing
# any command or replacing the connection: both writers receive the SAME real
# owned reference wrapper already installed by original application bootstrap.
class PortableDiscourseAccessorConsumer
  include Discourse
end
redis = Discourse.redis
accessor_consumer = PortableDiscourseAccessorConsumer.new
raise "module instance redis reader changed" unless accessor_consumer.redis.equal?(redis)
accessor_consumer.redis = redis
Discourse.redis = redis
raise "redis accessor writer changed identity" unless accessor_consumer.redis.equal?(Discourse.redis) && Discourse.redis.equal?(redis)
records << ["Discourse.redis[descriptor_and_shared_storage]", "value", "Array", [
  Discourse.method(:redis).arity, Discourse.method(:redis).parameters,
  Discourse.method(:redis=).arity, Discourse.method(:redis=).parameters,
  accessor_consumer.method(:redis).arity, accessor_consumer.method(:redis).parameters,
  accessor_consumer.method(:redis=).arity, accessor_consumer.method(:redis=).parameters,
]]

# Actual readonly lookup helpers: nil/false early-return negatives and real
# member/admin inputs. These are API records, NOT a claimed native identity matrix.
lookup_topics = Topic.order(:id).limit(4).to_a
lookup_categories = Category.order(:id).limit(4).pluck(:id)
[nil, false].each do |user|
  label = user.nil? ? "nil" : "false"
  capture_portable_setting(records, "CategoryUser.lookup_for[#{label}]") { CategoryUser.lookup_for(user, lookup_categories) }
  capture_portable_setting(records, "TopicUser.lookup_for[#{label}]") { TopicUser.lookup_for(user, lookup_topics) }
  capture_portable_setting(records, "DismissedTopicUser.lookup_for[#{label}]") { DismissedTopicUser.lookup_for(user, lookup_topics) }
end
[User.where(admin: false).order(:id).first, User.where(admin: true).order(:id).first].each do |user|
  raise "missing real identity input" unless user
  category_lookup = CategoryUser.lookup_for(user, lookup_categories)
  topic_lookup = TopicUser.lookup_for(user, lookup_topics)
  capture_portable_setting(records, "CategoryUser.lookup_for[user=#{user.id}]") do
    category_lookup.map { |key, row| [key, row.class.name, row.id, row.category_id, row.notification_level] }.sort
  end
  capture_portable_setting(records, "TopicUser.lookup_for[user=#{user.id}]") do
    topic_lookup.map { |key, row| [key, row.class.name, row.id, row.topic_id, row.notification_level] }.sort
  end
  capture_portable_setting(records, "DismissedTopicUser.lookup_for[user=#{user.id}]") { DismissedTopicUser.lookup_for(user, lookup_topics) }
  capture_portable_setting(records, "PostAction.lookup_for[user=#{user.id}]") do
    PostAction.lookup_for(user, lookup_topics, PostActionType.types[:like])
  end
  capture_portable_setting(records, "CategoryUser.indirectly_muted[user=#{user.id}]") do
    CategoryUser.indirectly_muted_category_ids(user)
  end
end

# Exact search escaping plus real DB unaccent/tsquery text, including SQL
# metacharacters/Unicode and a NUL rejection. No search result is frozen.
["plain", "O'Brien", "a\\b", "x'\\y", "café", "💬", "line\nnext", "\u0000"].each_with_index do |term, index|
  capture_portable_setting(records, "Search.escape_string[#{index}]") { Search.escape_string(term) }
  capture_portable_setting(records, "Search.unaccent[#{index}]") { Search.unaccent(term) }
  capture_portable_setting(records, "Search.ts_query[#{index}]") { Search.ts_query(term: term) }
end

# Labelled value-object UNIT input, never a production/native topic source.
poster_control = TopicPoster.new(flair_group: "unit initial", extra: false)
poster_control.user = "unit user"
poster_control.description = "unit description"
poster_control.extras = "unit extras"
poster_control.id = 123
poster_control.primary_group = "unit primary"
poster_control.flair_group = "unit flair"
poster_control[:extra] = 0
capture_portable_setting(records, "TopicPoster[unit attributes]") { poster_control.attributes }
capture_portable_setting(records, "TopicPoster[unit composed table]") { poster_control.to_h }
capture_portable_setting(records, "TopicPoster[unit flair]") { poster_control.flair_group }
capture_portable_setting(records, "TopicPoster[constructor parameters]") { TopicPoster.instance_method(:initialize).parameters }
%i[[] []= to_h each_pair dig delete_field freeze].each do |name|
  capture_portable_setting(records, "TopicPoster[#{name} parameters]") { TopicPoster.instance_method(name).parameters }
end
capture_portable_setting(records, "TopicPoster[flair writer parameters]") { poster_control.method(:flair_group=).parameters }
capture_portable_setting(records, "TopicPoster[block map]") { poster_control.to_h { |key, value| [key.to_s, value.to_s] } }
capture_portable_setting(records, "TopicPoster[each pairs]") { poster_control.each_pair.to_a }
capture_portable_setting(records, "TopicPoster[each returns self]") { poster_control.each_pair { |_pair| }.equal?(poster_control) }
capture_portable_setting(records, "TopicPoster[nested dig]") { TopicPoster.new(nested: {"x" => [7]}).dig(:nested, "x", 0) }
capture_portable_setting(records, "TopicPoster[missing flair reflection]") { TopicPoster.new.respond_to?(:flair_group) }
capture_portable_setting(records, "TopicPoster[present flair reflection]") { poster_control.respond_to?(:flair_group) }
capture_portable_setting(records, "TopicPoster[dynamic field]") do
  value = TopicPoster.new
  value.unit_dynamic = false
  [value.unit_dynamic, value.respond_to?(:unit_dynamic), value[:unit_dynamic], value.to_h]
end
capture_portable_setting(records, "TopicPoster[declared fields stay separate]") do
  value = TopicPoster.new(user: "table user", id: 7)
  value.user = "declared user"
  [value.user, value.id, value.to_h]
end
capture_portable_setting(records, "TopicPoster[copy isolation]") do
  value = TopicPoster.new(extra: 1)
  copy = value.dup
  copy[:extra] = 2
  [value[:extra], copy[:extra]]
end
capture_portable_setting(records, "TopicPoster[delete present]") { TopicPoster.new(extra: 1).delete_field(:extra) }
capture_portable_setting(records, "TopicPoster[delete absent fallback]") { TopicPoster.new.delete_field(:absent) { "fallback" } }
# Error descriptors avoid process addresses/receiver formatting, but retain the
# real public error class, missing method name, and argument contracts.
{
  "bad constructor" => -> { TopicPoster.new(1) },
  "constructor arity" => -> { TopicPoster.new({}, {}) },
  "bad read key" => -> { poster_control[1] },
  "bad write key" => -> { poster_control[1] = 2 },
  "bad dig key" => -> { poster_control.dig(1) },
  "missing field arguments" => -> { poster_control.unit_absent(1) },
  "writer arity" => -> { poster_control.public_send(:unit_unknown=, 1, 2) },
  "delete absent" => -> { TopicPoster.new.delete_field(:absent) },
  "frozen table" => -> { TopicPoster.new.freeze[:extra] = 1 },
  "frozen attribute" => -> { TopicPoster.new.freeze.user = "wrong" },
}.each do |label, operation|
  capture_portable_setting(records, "TopicPoster[#{label}]") do
    begin
      operation.call
      ["unexpected return"]
    rescue StandardError => error
      [error.class.name, error.respond_to?(:name) ? error.name.to_s : nil]
    end
  end
end

capture_portable_setting(records, "Topic[preload custom fields]") do
  topics = Topic.listable_topics.visible.secured(Guardian.new).order(:id).limit(3).to_a
  fields = ["accepted_answer_post_id", "_fidelity_missing_unit_field_"]
  Topic.preload_custom_fields(topics, fields)
  topics.map { |topic| [topic.id, topic.preloaded_custom_fields] }
end
%i[string integer boolean json].each do |type|
  capture_portable_setting(records, "CustomFieldDescriptor[#{type} unit]") do
    descriptor = HasCustomFields::FieldDescriptor.new(type, 10_000_000)
    values = {string: "plain", integer: "7", boolean: "t", json: '{"unit":false}'}
    output = {}
    descriptor.append_field(output, "unit", values[type])
    descriptor.append_field(output, "unit", values[type])
    output
  end
end

(Category.order(:id).limit(8).pluck(:id) + [-1, 0]).each do |category_id|
  capture_portable_setting(records, "Category.subcategory_ids[#{category_id}]") do
    [Category.subcategory_ids(category_id), Category.subcategory_ids(category_id)]
  end
end

# Actual public filter API; SQL and live IDs must retain all original joins,
# security predicates and order directions, including the instance-owned scopes.
[nil, User.where(admin: true).order(:id).first, User.where(admin: false).order(:id).first].uniq.each_with_index do |identity, index|
  %w[activity category likes-op likes-op-asc hot read read-asc title invalid-unit].each do |order|
    capture_portable_setting(records, "TopicsFilter[#{index} #{order}]") do
      filter = TopicsFilter.new(guardian: Guardian.new(identity))
      scope = filter.filter_from_query_string("order:#{order}")
      [scope.to_sql, scope.limit(8).pluck(:id), filter.invalid_filters]
    end
  end
end

# Labelled registry UNIT. No plugin is loaded, and no DB/cache setting is
# written: mutate real in-process registration storage, then restore identity.
raw_registry = DiscoursePluginRegistry._raw_topic_preloader_associations
saved_registry = raw_registry.dup
begin
  unit_plugin = Struct.new(:enabled?).new(true)
  disabled_unit_plugin = Struct.new(:enabled?).new(false)
  DiscoursePluginRegistry.register_topic_preloader_association("unit field", unit_plugin)
  DiscoursePluginRegistry.register_topic_preloader_association("unit field", unit_plugin)
  DiscoursePluginRegistry.register_topic_preloader_association("disabled field", disabled_unit_plugin)
  capture_portable_setting(records, "Registry[enabled unique unit]") { DiscoursePluginRegistry.topic_preloader_associations }
  unit_plugin[0] = false
  capture_portable_setting(records, "Registry[disabled refresh unit]") { DiscoursePluginRegistry.topic_preloader_associations }
  capture_portable_setting(records, "Registry[instance shortcut unit]") { DiscoursePluginRegistry.new.topic_preloader_associations }
  DiscoursePluginRegistry.reset_register!(:topic_preloader_associations)
  capture_portable_setting(records, "Registry[reset unit]") { DiscoursePluginRegistry.topic_preloader_associations }
  %i[topic_preloader_associations _raw_topic_preloader_associations register_topic_preloader_association].each do |name|
    capture_portable_setting(records, "Registry[#{name} parameters]") { DiscoursePluginRegistry.method(name).parameters }
  end
ensure
  raw_registry.replace(saved_registry)
  DiscoursePluginRegistry.instance_variable_set(:@topic_preloader_associations, raw_registry)
end

capture_portable_setting(records, "client_settings_hash") { SiteSetting.client_settings_hash }
capture_portable_setting(records, "client_settings_json_parsed") { JSON.parse(SiteSetting.client_settings_json) }
# Use the original public error and security APIs, not replacements.
capture_portable_setting(records, "theme_without_scope") { SiteSetting.get(:enable_welcome_banner) }
puts "FIDELITY_PORTABLE_RAILS " + JSON.generate({
  profile: SiteSetting.respond_to?(:portable_store) ? "PATCHED hybrid core-no-plugins" : "ORIGINAL core-no-plugins",
  records: records, count: records.length,
  scalar_getter_source: SiteSetting.method(:title).source_location,
  refresh_source: SiteSetting.method(:refresh!).source_location,
  special_getter_source: SiteSetting.method(:granular_anonymous_and_logged_in_groups_permissions).source_location,
  patched_model_sha256: Digest::SHA256.file(Rails.root.join("app/models/site_setting.rb")).hexdigest,
  native_full_site_setting_accepted: false, core_latest_accepted: false,
})

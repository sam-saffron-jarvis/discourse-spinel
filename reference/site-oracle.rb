# Run with `cd ../discourse && bin/rails runner ../minimal/reference/site-oracle.rb`.
# All probes use a read-only PG transaction. Prints names/counts only, never bodies.
require "json"
require_relative "native_site"

expected_database_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
expected_redis_url = "redis://127.0.0.1:6399/0"
abort "wrong task database" unless ENV["DATABASE_URL"] == expected_database_url
abort "wrong task Valkey" unless ENV["REDIS_URL"] == expected_redis_url

SITE_FIELDS = %w[
  default_archetype notification_types post_types trust_levels filters
  anonymous_list_filters periods archetypes top_menu_items anonymous_top_menu_items
  can_create_tag can_search can_tag_topics can_tag_pms hashtag_icons categories
].freeze

# A separate savepoint isolates Site.json_for's write-on-read error while leaving
# the outer read-only transaction usable for safe direct serializer getters.
def capture_full_site_api(connection)
  error = nil
  ActiveRecord::Base.transaction(requires_new: true) do
    begin
      Site.json_for(Guardian.new)
    rescue => caught
      error = caught
      raise ActiveRecord::Rollback
    end
  end
  return { "completed" => true } unless error

  source_frames = error.backtrace.filter_map do |frame|
    frame if frame.include?("/discourse/lib/") || frame.include?("/discourse/app/")
  end.first(12)
  {
    "completed" => false,
    "exception" => error.class.name,
    "message" => error.message,
    "source_frames" => source_frames,
  }
end

def json_value(value)
  JSON.parse(ActiveSupport::JSON.encode(value))
end

conn = ActiveRecord::Base.connection.raw_connection
report = nil
begin
  ActiveRecord::Base.transaction do
    conn.exec("SET TRANSACTION READ ONLY")
    full_api = capture_full_site_api(conn)

    # Compare the actual serializer field implementations individually. This
    # avoids calling the one known write-on-read wizard field while preserving
    # the evidence that the public aggregate API could not complete.
    guardian = Guardian.new
    site = Site.new(guardian)
    serializer = SiteSerializer.new(site, root: false, scope: guardian)
    actual_site = {}
    field_errors = {}
    SITE_FIELDS.each do |field|
      begin
        value = case field
        when "notification_types" then site.notification_types
        when "trust_levels" then site.trust_levels
        when "archetypes"
          site.archetypes.map { |item| ArchetypeSerializer.new(item, root: false, scope: guardian).as_json }
        else serializer.public_send(field)
        end
        actual_site[field] = json_value(value)
      rescue => error
        field_errors[field] = error.class.name
      end
    end

    actual_settings = JSON.parse(SiteSetting.client_settings_json)
    native_site = JSON.parse(NativeReference.site_json(conn))
    native_settings = NativeReference.read_client_settings(conn)
    scalar_fields = SITE_FIELDS - ["categories"]
    missing_native = scalar_fields.reject { |field| native_site.key?(field) }
    missing_rails = scalar_fields.reject { |field| actual_site.key?(field) }
    mismatched_site_fields = scalar_fields.select do |field|
      actual_site.key?(field) && native_site.key?(field) && actual_site[field] != native_site[field]
    end

    actual_categories = actual_site.fetch("categories", [])
    native_categories = native_site.fetch("categories", [])
    actual_by_id = actual_categories.to_h { |category| [category.fetch("id"), category] }
    native_by_id = native_categories.to_h { |category| [category.fetch("id"), category] }
    category_order_matches = actual_categories.map { |category| category.fetch("id") } ==
      native_categories.map { |category| category.fetch("id") }
    category_field_mismatches = []
    category_unrepresented_fields = {}
    native_categories.each do |native_category|
      id = native_category.fetch("id")
      actual_category = actual_by_id[id]
      next unless actual_category
      native_category.each do |field, value|
        if !actual_category.key?(field) || actual_category[field] != value
          category_field_mismatches << field unless category_field_mismatches.include?(field)
        end
      end
      omitted = actual_category.keys - native_category.keys
      category_unrepresented_fields[id] = omitted unless omitted.empty?
    end

    safe_names = NativeReference::CLIENT_SETTINGS.keys
    comparable_settings = safe_names.select { |name| actual_settings.key?(name) }
    setting_mismatches = comparable_settings.filter_map do |name|
      name unless actual_settings[name] == native_settings[name]
    end
    report = {
      "source_revision" => NativeReference::SOURCE_REVISION,
      "site_json_for" => full_api,
      "site_field_comparison" => {
        "method" => "actual SiteSerializer/Site methods, field-by-field under the same read-only transaction",
        "compared_fields" => scalar_fields,
        "categories_compared_separately" => true,
        "field_errors" => field_errors,
        "missing_native_fields" => missing_native,
        "missing_actual_fields" => missing_rails,
        "mismatched_fields" => mismatched_site_fields,
        "matches" => field_errors.empty? && missing_native.empty? && mismatched_site_fields.empty?,
      },
      "categories" => {
        "ordered_ids_match" => category_order_matches,
        "native_category_count" => native_categories.length,
        "category_field_mismatches" => category_field_mismatches.uniq,
        "unrepresented_actual_field_names" => category_unrepresented_fields.values.flatten.uniq.sort,
        "unrepresented_actual_field_count" => category_unrepresented_fields.values.sum(&:length),
        "all_emitted_fields_match" => category_order_matches && category_field_mismatches.empty?,
      },
      "client_settings_json" => {
        "full_api_completed" => true,
        "safe_allowlist_count" => safe_names.length,
        "comparable_count" => comparable_settings.length,
        "mismatched_names" => setting_mismatches,
        "not_returned_by_rails_api" => safe_names - comparable_settings,
        "unrepresented_rails_client_setting_count" => (actual_settings.keys - safe_names).length,
        "unallowlisted_database_settings_excluded" => (native_settings.keys - safe_names).empty?,
        "matches_source_core_subset" => setting_mismatches.empty? && (safe_names - comparable_settings).empty?,
        "matches_complete_rails_catalog" => setting_mismatches.empty? && (safe_names - comparable_settings).empty? && (actual_settings.keys - safe_names).empty?,
        "matches" => setting_mismatches.empty? && (safe_names - comparable_settings).empty? && (actual_settings.keys - safe_names).empty?,
      },
      "read_only" => true,
    }
  end
  puts JSON.pretty_generate(report)
  abort "site/settings oracle mismatch" unless report.dig("site_field_comparison", "matches") &&
    report.dig("categories", "all_emitted_fields_match") &&
    report.dig("client_settings_json", "matches_source_core_subset")
rescue => error
  warn JSON.generate("oracle_blocked" => error.class.name, "message" => error.message,
                     "read_only" => true)
  exit 2
end

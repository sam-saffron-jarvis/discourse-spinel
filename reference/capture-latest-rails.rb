# Run from the Discourse Rails checkout with `bin/rails runner`.
# This is a verification capture, never a response source. The transaction is
# explicitly read-only so a Rails callback attempting a DB write fails closed.
require "action_dispatch/testing/integration"
require "json"
require "time"

expected_database_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
expected_redis_url = "redis://127.0.0.1:6399/0"
abort "DATABASE_URL must be #{expected_database_url}" unless ENV["DATABASE_URL"] == expected_database_url
abort "REDIS_URL must be #{expected_redis_url}" unless ENV["REDIS_URL"] == expected_redis_url

connection = ActiveRecord::Base.connection
captured = {}
connection.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host!("localhost")
  { "latest" => "/latest.json", "latest_page_1" => "/latest.json?page=1" }.each do |name, path|
    session.get(path, headers: { "Accept" => "application/json" })
    abort "GET #{path} returned #{session.response.status}" unless session.response.status == 200
    abort "GET #{path} did not return JSON" unless session.response.media_type == "application/json"
    captured[name] = {
      "path" => path,
      "status" => session.response.status,
      "body" => JSON.parse(session.response.body),
    }
  end

  latest_body = captured.fetch("latest").fetch("body")
  topic_ids = latest_body.fetch("topic_list").fetch("topics").map { |topic| topic.fetch("id") }
  listed_rows = Topic.unscoped.where(id: topic_ids).pluck(:id, :visible, :archetype, :deleted_at)
  abort "listed topic missing or not visible/listable" unless listed_rows.length == topic_ids.length &&
    listed_rows.all? { |_, visible, archetype, deleted_at| visible && archetype != Archetype.private_message && deleted_at.nil? }

  restricted_categories = Category.where(read_restricted: true).pluck(:id, :name)
  restricted_topic_ids = Topic.unscoped.where(category_id: restricted_categories.map(&:first)).pluck(:id)
  definition_topic_ids = Category.where.not(topic_id: nil).pluck(:topic_id)
  unlisted_topic_ids = Topic.unscoped.where(visible: false).pluck(:id)
  deleted_topic_ids = Topic.unscoped.where.not(deleted_at: nil).pluck(:id)
  private_message_topic_ids = Topic.unscoped.where(archetype: Archetype.private_message).pluck(:id)
  abort "anonymous latest leaked a restricted-category topic" unless (topic_ids & restricted_topic_ids).empty?
  if !SiteSetting.show_category_definitions_in_topic_lists
    abort "latest included category-definition topics despite setting" unless (topic_ids & definition_topic_ids).empty?
  end
  abort "anonymous latest leaked an unlisted topic" unless (topic_ids & unlisted_topic_ids).empty?
  abort "anonymous latest leaked a deleted topic" unless (topic_ids & deleted_topic_ids).empty?
  abort "anonymous latest leaked a private-message topic" unless (topic_ids & private_message_topic_ids).empty?

  ordered = latest_body.fetch("topic_list").fetch("topics")
  row_lookup = Topic.unscoped.where(id: topic_ids).index_by(&:id)
  global_pins = topic_ids.select { |id| row_lookup[id].pinned_globally && row_lookup[id].pinned_at }
  expected_pins = global_pins.sort_by { |id| row_lookup[id].pinned_at }.reverse
  abort "global pins must lead in pinned_at descending order" unless topic_ids.first(global_pins.length) == expected_pins
  unpinned_ids = topic_ids - global_pins
  bumped_times = unpinned_ids.map { |id| row_lookup[id].bumped_at }
  abort "unpinned latest order is not bumped_at descending" unless bumped_times == bumped_times.sort.reverse

  pagination_urls = [
    Rails.application.routes.url_helpers.latest_path(no_definitions: true, page: 1, format: :json).sub(".json?", "?"),
    Rails.application.routes.url_helpers.latest_path(page: 2, format: :json).sub(".json?", "?"),
  ]
  abort "pagination route contract changed" unless pagination_urls == ["/latest?no_definitions=true&page=1", "/latest?page=2"]

  captured["db_audit"] = {
    "full_page_pagination_urls" => pagination_urls,
    "listed_topic_count" => topic_ids.length,
    "listed_topic_ids" => topic_ids,
    "all_listed_rows_visible_regular_not_deleted" => true,
    "restricted_categories" => restricted_categories.map { |id, name| { "id" => id, "name" => name } },
    "restricted_category_topic_ids_in_database" => restricted_topic_ids.sort,
    "restricted_category_topic_ids_excluded" => (topic_ids & restricted_topic_ids).empty?,
    "category_definition_count" => definition_topic_ids.length,
    "category_definition_topic_ids" => definition_topic_ids.sort,
    "category_definition_setting" => SiteSetting.show_category_definitions_in_topic_lists,
    "category_definitions_omitted_when_disabled" =>
      !SiteSetting.show_category_definitions_in_topic_lists ? (topic_ids & definition_topic_ids).empty? : nil,
    "unlisted_topic_ids_in_database" => unlisted_topic_ids.sort,
    "deleted_topic_ids_in_database" => deleted_topic_ids.sort,
    "private_message_topic_ids_in_database" => private_message_topic_ids.sort,
    "unpinned_bumped_at_descending" => true,
    "global_pins_first_pinned_at_descending" => true,
  }
end
puts JSON.pretty_generate(
  "capture_kind" => "static verification only; never serve as runtime data",
  "source_revision" => `git rev-parse HEAD`.strip,
  "responses" => captured,
)

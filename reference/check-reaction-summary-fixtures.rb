# frozen_string_literal: true
# TEST ONLY: actual pinned CustomReactionsController#post_reactions_users and
# its helpers over the same synthetic, read-only typed CTE rows as the native fixture.
require "json"
require "active_support/testing/time_helpers"
extend ActiveSupport::Testing::TimeHelpers
abort "task DB required" unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"
abort "task Valkey required" unless ENV["REDIS_URL"] == "redis://127.0.0.1:6399/0"
root = File.expand_path("..", __dir__)
fixtures = JSON.parse(File.read(File.join(root, "build/reaction-summary-fixtures-native.json")))
abort "fixture must be synthetic and read-only" unless fixtures["synthetic"] == true && fixtures["read_only"] == true
abort "unexpected fixture tables" unless fixtures.fetch("tables").keys.sort == %w[users discourse_reactions_reactions discourse_reactions_reaction_users post_actions].sort

connection = ActiveRecord::Base.connection
# Load schemas before CTE-only query adaptation, matching the existing reactions fixture.
[User, PostAction, DiscourseReactions::Reaction, DiscourseReactions::ReactionUser, Post, Topic, Category, SharedDraft].each(&:columns)
cte = "WITH " + fixtures.fetch("tables").map do |table, rows|
  "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table},#{connection.quote(JSON.generate(rows))}::json))"
end.join(", ") + ", "

module ReactionSummaryFixtureRawExecute
  private
  def raw_execute(sql, *args, **kwargs, &block)
    prefix = Thread.current[:reaction_summary_cte]
    sql = prefix.sub(/,\s*\z/, " ") + sql if prefix && sql.lstrip.start_with?("SELECT")
    super(sql, *args, **kwargs, &block)
  end
end
connection.singleton_class.prepend(ReactionSummaryFixtureRawExecute)

# Settings are thread-local process stubs only: no database setting write.
module ReactionSummaryFixtureSettings
  def discourse_reactions_enabled_reactions
    Thread.current[:reaction_summary_settings]&.fetch("enabled_reactions") || super
  end
  def discourse_reactions_reaction_for_like
    Thread.current[:reaction_summary_settings]&.fetch("main") || super
  end
  def enable_names?
    value = Thread.current[:reaction_summary_settings]&.fetch("names_enabled")
    value.nil? ? super : value
  end
  def post_undo_action_window_mins
    Thread.current[:reaction_summary_settings]&.fetch("undo_minutes") || super
  end
end
SiteSetting.singleton_class.prepend(ReactionSummaryFixtureSettings)

FixturePost = Struct.new(:id) do
  def post_actions = PostAction.where(post_id: id)
  def reactions = DiscourseReactions::Reaction.where(post_id: id)
end
source_guardian = Guardian.new(nil)

controller_class = DiscourseReactions::CustomReactionsController
source_cases = []
visibility_cases = []
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  connection.execute("SET LOCAL TIME ZONE 'UTC'")
  ActiveRecord::Base.uncached do
    fixtures.fetch("cases").each do |fixture|
      settings = fixture.slice("enabled_reactions", "main", "names_enabled", "undo_minutes")
      Thread.current[:reaction_summary_settings] = settings
      Thread.current[:reaction_summary_cte] = cte
      filter = fixture.fetch("filter")
      post_id = fixture.fetch("post_id")
      params = ActionController::Parameters.new({ "id" => post_id.to_s }.tap { |value| value["reaction_value"] = filter unless filter.nil? })
      controller = controller_class.new
      result = nil
      controller.define_singleton_method(:params) { params }
      controller.define_singleton_method(:render_json_dump) { |payload| result = payload }
      controller.define_singleton_method(:fetch_post_from_params) { FixturePost.new(post_id) }
      controller.define_singleton_method(:current_user) { nil }
      controller.define_singleton_method(:guardian) { source_guardian }
      begin
        travel_to(Time.at(fixture.fetch("now")).utc, with_usec: true) do
          controller.post_reactions_users
        end
      ensure
        Thread.current[:reaction_summary_cte] = nil
        Thread.current[:reaction_summary_settings] = nil
      end
      actual = result || raise("source action did not render for #{fixture.inspect}")
      expected = { "reaction_users" => fixture.fetch("reaction_users") }
      canonical = JSON.parse(ActiveSupport::JSON.encode(actual))
      raise "actual source action/helper mismatch for filter=#{filter.inspect}: #{canonical.inspect}" unless canonical == expected
      source_cases << { "filter" => filter, "post_id" => post_id, "reaction_users" => canonical.fetch("reaction_users") }
    end
    visibility = fixtures.fetch("visibility")
    raise "unexpected visibility tables" unless visibility.fetch("tables").keys.sort == %w[posts topics categories shared_drafts].sort
    visibility_cte = "WITH " + visibility.fetch("tables").map do |table, rows|
      "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table},#{connection.quote(JSON.generate(rows))}::json))"
    end.join(", ") + ", "
    visibility.fetch("cases").each do |fixture|
      controller = controller_class.new
      params = ActionController::Parameters.new(id: fixture.fetch("id").to_s)
      controller.define_singleton_method(:params) { params }
      controller.define_singleton_method(:guardian) { Guardian.new(nil) }
      begin
        Thread.current[:reaction_summary_cte] = visibility_cte
        status = begin
          controller.send(:fetch_post_from_params)
          200
        rescue ActiveRecord::RecordNotFound
          404
        rescue Discourse::InvalidAccess
          403
        end
      ensure
        Thread.current[:reaction_summary_cte] = nil
      end
      actual = { "id" => fixture.fetch("id"), "status" => status }
      raise "actual source fetch_post/Guardian mismatch #{actual} versus #{fixture}" unless actual == fixture
      visibility_cases << actual
    end
  end
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate({
  "label" => "synthetic typed SELECT-only CTE fixtures; actual pinned post_reactions_users action and helpers, not live reaction data",
  "source_revision" => `git -C #{File.expand_path("../../discourse", __dir__)} rev-parse HEAD`.strip,
  "read_only" => true,
  "case_count" => source_cases.length,
  "cases" => source_cases,
  "source_fetch_post_guardian_visibility" => visibility_cases,
})

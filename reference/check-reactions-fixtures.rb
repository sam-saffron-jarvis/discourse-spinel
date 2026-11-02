# frozen_string_literal: true
# TEST ONLY: executes the unchanged actual plugin query and format_user against
# source-driven synthetic CTE rows. No table writes/DDL, no runtime dependency.
require "json"
abort "task DB required" unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"
abort "task Valkey required" unless ENV["REDIS_URL"] == "redis://127.0.0.1:6399/0"
root = File.expand_path("..", __dir__)
fixtures = JSON.parse(File.read(File.join(root, "build/reactions-fixtures-native.json")))
connection = ActiveRecord::Base.connection
allowed_tables = %w[users discourse_reactions_reactions discourse_reactions_reaction_users post_actions]
abort "unexpected fixture table" unless fixtures.fetch("tables").keys.sort == allowed_tables.sort
# Warm schema/type dependencies BEFORE enabling the CTE-only row adapter.
[User, PostAction, DiscourseReactions::Reaction, DiscourseReactions::ReactionUser, Post, Topic, Category, SharedDraft].each(&:columns)
cte = "WITH " + fixtures.fetch("tables").map do |table, rows|
  "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table},#{connection.quote(JSON.generate(rows))}::json))"
end.join(", ") + " "

# These adapters only supply read-only synthetic tables to the unchanged SQL;
# they neither replace query results nor reimplement the source rows/total logic.
module ReactionsFixtureMiniSql
  def query(sql, *params)
    prefix = Thread.current[:reactions_fixture_cte]
    if prefix && sql.lstrip.start_with?("SELECT")
      # Bind source SQL BEFORE adding JSON (whose :null text isn't a bind).
      super(prefix + to_sql(sql, *params))
    else
      super(sql, *params)
    end
  end
end
module ReactionsFixtureActiveRecord
  private
  def raw_execute(sql, *args, **kwargs, &block)
    prefix = Thread.current[:reactions_fixture_cte]
    sql = prefix + sql if prefix && sql.lstrip.start_with?("SELECT")
    super(sql, *args, **kwargs, &block)
  end
end
DB.singleton_class.prepend(ReactionsFixtureMiniSql)
connection.singleton_class.prepend(ReactionsFixtureActiveRecord)
module ReactionsFixtureNames
  def enable_names?
    value = Thread.current[:reactions_fixture_names]
    value.nil? ? super : value
  end
end
SiteSetting.singleton_class.prepend(ReactionsFixtureNames)
controller = DiscourseReactions::CustomReactionsController.new
cases = []
visibility_cases = []
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  ActiveRecord::Base.uncached do
    fixtures.fetch("cases").each do |fixture|
      query = DiscourseReactions::PostReactionsQuery.new(
        post: Struct.new(:id).new(fixture.fetch("post_id")),
        reaction_filter: fixture.fetch("filter"), limit: fixture.fetch("limit"),
        offset: fixture.fetch("offset"), current_user_id: nil,
      )
      # Main-reaction setting is a test dependency, not a mutation of shared PG.
      main = fixture.fetch("main")
      query.define_singleton_method(:main_reaction) { main }
      begin
        Thread.current[:reactions_fixture_cte] = cte
        rows = query.rows
        total = query.total
      ensure
        Thread.current[:reactions_fixture_cte] = nil
      end
      raw = rows.map do |row|
        row.to_h.transform_keys(&:to_s).except("created_at")
      end
      expected = fixture.fetch("rows").map { |row| row.except("created_at") }
      raise "actual source rows mismatch for #{fixture.inspect}" unless raw == expected
      raise "actual source total mismatch for #{fixture.inspect}: #{total}" unless total == fixture.fetch("total")
      begin
        Thread.current[:reactions_fixture_names] = fixture.fetch("names_enabled")
        users = rows.map do |row|
          controller.send(:format_user, row, id: row.id,
            avatar_template: User.avatar_template(row.username, row.uploaded_avatar_id), reaction: row.reaction).transform_keys(&:to_s)
        end
      ensure
        Thread.current[:reactions_fixture_names] = nil
      end
      if fixture.key?("users")
        raise "actual source serialization mismatch" unless users == fixture.fetch("users")
      end
      cases << { "filter" => fixture.fetch("filter"), "main" => main,
        "limit" => fixture.fetch("limit"), "offset" => fixture.fetch("offset"),
        "rows" => raw, "total" => total, "users" => users, "names_enabled" => fixture.fetch("names_enabled") }
    end
    visibility = fixtures.fetch("visibility")
    raise "unexpected visibility table" unless visibility.fetch("tables").keys.sort == %w[posts topics categories shared_drafts].sort
    visibility_cte = "WITH " + visibility.fetch("tables").map do |table, rows|
      "#{table} AS (SELECT * FROM json_populate_recordset(NULL::public.#{table},#{connection.quote(JSON.generate(rows))}::json))"
    end.join(", ") + " "
    visibility.fetch("cases").each do |fixture|
      begin
        Thread.current[:reactions_fixture_cte] = visibility_cte
        begin
          post = Post.find(fixture.fetch("id"))
          found = true
          allowed = !!Guardian.new(nil).can_see?(post)
        rescue ActiveRecord::RecordNotFound
          found = false
          allowed = false
        end
      ensure
        Thread.current[:reactions_fixture_cte] = nil
      end
      actual = { "id" => fixture.fetch("id"), "found" => found, "allowed" => allowed }
      raise "source Guardian visibility mismatch #{actual} versus #{fixture}" unless actual == fixture
      visibility_cases << actual
    end
  end
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate({ "label" => "synthetic SELECT-only CTE fixtures; actual upstream PostReactionsQuery rows/total and format_user, NOT live reaction data",
  "source_revision" => `git rev-parse HEAD`.strip, "read_only" => true,
  "cases" => cases, "case_count" => cases.length, "source_guardian_visibility" => visibility_cases })

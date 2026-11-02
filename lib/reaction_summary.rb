# frozen_string_literal: true
# GPL-2.0-or-later. Distinct anonymous grouped summary source adaptation.
# See reference/reaction-summary-contract.md; NOT the users-list query.
require_relative "reactions"

class NativeReactionSummaryRequest
  attr_reader :id, :reaction_filter

  def initialize(path, query)
    match = path.match(/\A\/discourse-reactions\/posts\/(0|[1-9]\d{0,9})\/reactions-users(?:\.json)?\z/)
    raise ArgumentError, "invalid reaction summary route" unless match && match[1].to_s.to_i <= 2147483647
    @id = match[1].to_s.to_i
    raise ArgumentError, "reaction summary query too large" if query.bytesize > 2048
    raise ArgumentError, "invalid query encoding" if query.gsub(/%[a-fA-F0-9]{2}/, "").include?("%")
    @reaction_filter = nil
    seen = false
    URI.decode_www_form(query).each do |pair|
      key, value = pair
      raise ArgumentError, "unsupported or duplicate summary parameter" unless key == "reaction_value" && !seen
      raise ArgumentError, "reaction summary parameter too large" if value.bytesize > 256
      raise ArgumentError, "invalid reaction summary parameter" if value.include?("\0") || value.include?("\uFFFD")
      seen = true
      @reaction_filter = value
    end
  end
end

class NativeReactionSummarySettings < NativeReactionsSettings
  NAMES = (NativeReactionsSettings::NAMES + %w[discourse_reactions_enabled_reactions post_undo_action_window_mins use_site_small_logo_as_system_avatar logo_small]).freeze

  def initialize(conn)
    @values = {}
    rows = conn.exec_params("SELECT name, value FROM site_settings WHERE name = ANY($1::text[])", ["{#{NAMES.join(',')}}"])
    rows.ntuples.times { |i| @values[rows.getvalue(i, 0).to_s] = rows.getvalue(i, 1).to_s }
  end
end

class NativeReactionSummary < NativeReactions
  MAX_USERS_COUNT = 26
  DEFAULT_ENABLED_REACTIONS = "+1|laughing|open_mouth|clap|confetti_ball|hugs"
  PARAMS = "WITH summary_params AS (SELECT $1::integer, $2::text, $3::text) "
  # No enabled-value filter or invented order: source post.reactions association.
  def self.reactions_sql(filter, main)
    condition = if filter.nil?
      "reaction_value IS DISTINCT FROM $2::text"
    elsif filter != main
      "reaction_value = $3::text"
    else
      "FALSE"
    end
    PARAMS + "SELECT row_to_json(r) FROM (SELECT id, reaction_value, reaction_users_count FROM discourse_reactions_reactions WHERE post_id=$1::integer AND reaction_users_count IS NOT NULL AND (#{condition})) r"
  end

  def self.main_sql
    PARAMS + "SELECT row_to_json(r) FROM (SELECT id, reaction_value, reaction_users_count FROM discourse_reactions_reactions WHERE post_id=$1::integer AND reaction_value=$2::text LIMIT 1) r"
  end

  # Exact anonymous filter_reaction_likes_sql followed by the controller's
  # historical_reaction_likes exclusion. Unlike010 this uses VALID values first,
  # then excludes disabled historical likes; SQL NULL semantics are retained.
  LIKE_FILTER = <<~SQL
    post_actions.post_id=$1::integer
    AND post_actions.post_action_type_id=2 AND post_actions.deleted_at IS NULL
    AND post_actions.post_id NOT IN (
      SELECT discourse_reactions_reaction_users.post_id
      FROM discourse_reactions_reaction_users
      INNER JOIN discourse_reactions_reactions ON discourse_reactions_reactions.id=discourse_reactions_reaction_users.reaction_id
      WHERE discourse_reactions_reaction_users.user_id=post_actions.user_id
        AND discourse_reactions_reaction_users.post_id=post_actions.post_id
        AND discourse_reactions_reactions.reaction_value=ANY($2::text[])
    )
    AND post_actions.id NOT IN (
      SELECT historical_likes.id FROM post_actions historical_likes
      LEFT JOIN discourse_reactions_reaction_users historical_users
        ON historical_users.user_id=historical_likes.user_id AND historical_users.post_id=historical_likes.post_id
      LEFT JOIN discourse_reactions_reactions historical_reactions ON historical_reactions.id=historical_users.reaction_id
      WHERE historical_likes.post_id=$1::integer
        AND historical_likes.post_action_type_id=2 AND historical_likes.deleted_at IS NULL
        AND historical_likes.post_id NOT IN (
          SELECT discourse_reactions_reaction_users.post_id FROM discourse_reactions_reaction_users
          INNER JOIN discourse_reactions_reactions ON discourse_reactions_reactions.id=discourse_reactions_reaction_users.reaction_id
          WHERE discourse_reactions_reaction_users.user_id=historical_likes.user_id
            AND discourse_reactions_reaction_users.post_id=historical_likes.post_id
            AND discourse_reactions_reactions.reaction_value=ANY($2::text[])
        )
        AND NOT (historical_reactions.reaction_value=ANY($2::text[]))
    )
  SQL
  LIKE_PARAMS = "WITH summary_like_params AS (SELECT $1::integer, $2::text[], $3::text) "

  def self.likes_sql
    LIKE_PARAMS + "SELECT row_to_json(r) FROM (SELECT post_actions.id, post_actions.user_id, post_actions.created_at FROM post_actions WHERE #{LIKE_FILTER}) r"
  end

  def self.like_users_sql
    # Source likes.includes(:user).limit(27) applies the limit BEFORE loading
    # users; LEFT JOIN retains missing-user rows so serialization fails closed.
    LIKE_PARAMS + "SELECT row_to_json(r) FROM (SELECT u.id, u.username, u.name, u.uploaded_avatar_id, to_char(l.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') || ' UTC' AS created_at, FALSE AS can_undo FROM (SELECT post_actions.user_id, post_actions.created_at FROM post_actions WHERE #{LIKE_FILTER} LIMIT 27) l LEFT JOIN users u ON u.id=l.user_id) r"
  end

  def self.users_sql
    <<~SQL
      SELECT row_to_json(r) FROM (
        SELECT u.id, u.username, u.name, u.uploaded_avatar_id,
          to_char(ru.created_at AT TIME ZONE 'UTC', 'YYYY-MM-DD HH24:MI:SS') || ' UTC' AS created_at,
          (ru.created_at > to_timestamp($3::double precision) AT TIME ZONE 'UTC' - $2::integer * INTERVAL '1 minute') AS can_undo
        FROM (SELECT user_id, created_at FROM discourse_reactions_reaction_users
          WHERE reaction_id=$1::bigint ORDER BY created_at DESC LIMIT 27) ru
        LEFT JOIN users u ON u.id=ru.user_id ORDER BY ru.created_at DESC
      ) r
    SQL
  end

  def self.pg_array(values)
    "{" + values.map { |value| '"' + value.gsub(/[\\"]/) { |char| "\\" + char } + '"' }.join(",") + "}"
  end

  def self.json_rows(conn, sql, binds)
    rows = conn.exec_params(sql, binds)
    result = []
    rows.ntuples.times { |i| result << JSON.parse(rows.getvalue(i, 0).to_s) }
    result
  end

  def self.serialize_summary_user(row, settings)
    raise "reaction summary user missing" if row["id"].nil? || row["username"].nil?
    raise "unsupported reactions default avatars" unless settings.value("default_avatars", "").empty?
    result = { "username" => row["username"] }
    result["name"] = row["name"] if settings.enabled?("enable_names", true)
    # Source INSTANCE method, including the system-user small-logo shortcut.
    if row["id"].to_i == -1 && settings.enabled?("use_site_small_logo_as_system_avatar", true)
      raise "unsupported reaction summary system logo" unless settings.value("logo_small", "-6") == "-6"
    end
    result["avatar_template"] = NativeUsers.avatar_template(row, settings)
    result["can_undo"] = row["can_undo"]
    result["created_at"] = row["created_at"]
    result
  end

  def self.summary(conn, post_id, filter, settings, now = Time.now.to_f)
    main = settings.value("discourse_reactions_reaction_for_like", "heart").gsub("-", "")
    binds = [post_id.to_s, main, filter.to_s]
    reactions = json_rows(conn, reactions_sql(filter, main), binds)
    undo_mins = settings.value("post_undo_action_window_mins", "10")
    result = []
    if filter.nil? || filter == main
      valid = [main, *settings.value("discourse_reactions_enabled_reactions", DEFAULT_ENABLED_REACTIONS).split("|")].uniq
      like_binds = [post_id.to_s, pg_array(valid), ""]
      likes = json_rows(conn, likes_sql, like_binds)
      main_reaction = json_rows(conn, main_sql, binds).first
      # Source omits historical main ReactionUsers entirely unless likes.present?.
      unless likes.empty?
        count = likes.length
        users = json_rows(conn, like_users_sql, like_binds).map { |row| serialize_summary_user(row, settings) }
        if main_reaction && !main_reaction["reaction_users_count"].nil?
          users.concat(json_rows(conn, users_sql, [main_reaction["id"].to_s, undo_mins, now.to_s]).map { |row| serialize_summary_user(row, settings) })
          users.sort_by! { |user| user["created_at"].to_s }
          count += main_reaction["reaction_users_count"].to_i
        end
        result << { "id" => main, "count" => count, "users" => users.reverse.slice(0, MAX_USERS_COUNT + 1) }
      end
    end
    reactions.each do |reaction|
      users = json_rows(conn, users_sql, [reaction["id"].to_s, undo_mins, now.to_s]).map { |row| serialize_summary_user(row, settings) }
      result << { "id" => reaction["reaction_value"], "count" => reaction["reaction_users_count"].to_i, "users" => users }
    end
    { "reaction_users" => result }
  end

  def call(request)
    @conn.exec("BEGIN READ ONLY ISOLATION LEVEL REPEATABLE READ")
    begin
      settings = NativeReactionSummarySettings.new(@conn)
      status = NativeReactions.access_status(settings, true, true)
      return [status, JSON.generate({ "error" => "plugin disabled or anonymous access denied" })] unless status == 200
      post = @conn.exec_params(POST_QUERY, [request.id.to_s, settings.hidden_visible? ? "true" : "false"])
      status = NativeReactions.access_status(settings, post.ntuples > 0, post.ntuples > 0 && post.getvalue(0, 1).to_s == "t")
      return [status, JSON.generate({ "error" => "post not found or inaccessible" })] unless status == 200
      [200, JSON.generate(self.class.summary(@conn, request.id, request.reaction_filter, settings))]
    ensure
      @conn.exec("ROLLBACK")
    end
  end
end

# frozen_string_literal: true
# GPL-2.0-or-later. Anonymous source adaptation, NOT a Rails/plugin runtime.
# Original source copies and exact boundaries: reference/reactions-contract.md.
require "json"
require "uri"
require_relative "latest"

class NativeReactionsRequest
  attr_reader :id, :page, :limit, :reaction_filter

  def initialize(path, query)
    match = path.match(/\A\/discourse-reactions\/posts\/(0|[1-9]\d{0,9})\/reactions-users-list(?:\.json)?\z/)
    raise ArgumentError, "invalid reactions route" unless match && match[1].to_s.to_i <= 2147483647
    @id = match[1].to_s.to_i
    raise ArgumentError, "reactions query too large" if query.bytesize > 2048
    raise ArgumentError, "invalid query encoding" if query.gsub(/%[a-fA-F0-9]{2}/, "").include?("%")
    params = {}
    URI.decode_www_form(query).each do |pair|
      key, value = pair
      raise ArgumentError, "unsupported or duplicate reactions parameter" unless %w[page limit reaction_value].include?(key) && !params.key?(key)
      raise ArgumentError, "reactions parameter too large" if value.bytesize > 256
      raise ArgumentError, "invalid reactions parameter" if value.include?("\0") || value.include?("\uFFFD")
      params[key] = value
    end
    @page = [scalar_integer(params.fetch("page", "")), 0].max
    text = params.fetch("limit", "")
    @limit = self.class.blank?(text) ? 30 : [[scalar_integer(text), 1].max, 50].min
    @reaction_filter = params.fetch("reaction_value", "")
  end

  def self.blank?(text)
    # Discourse loads fast_blank1.0.1's rb_str_blank (ASCII rb_isspace + NUL),
    # not ActiveSupport's Unicode blank_as? predicate. HTTP NULs are rejected.
    text.match?(/\A[ \t\r\n\f\v\0]*\z/)
  end

  # Source String#to_i, including blank/junk/decimal-prefix values, then clamp.
  # Huge integer prefixes are explicitly unsupported, never overflow silently.
  def scalar_integer(text)
    match = text.match(/\A\s*([+-]?\d(?:_?\d)*)/)
    return 0 unless match
    value = match[1].to_s.gsub("_", "")
    raise ArgumentError, "reactions integer out of supported range" if value.length > 11 || value.to_i < -2147483648 || value.to_i > 2147483647
    value.to_i
  end
end

class NativeReactionsSettings < NativeSettings
  NAMES = %w[login_required enable_names default_avatars external_system_avatars_url restrict_letter_avatar_colors discourse_reactions_enabled discourse_reactions_reaction_for_like granular_anonymous_and_logged_in_groups_permissions hidden_post_visible_groups].freeze

  def initialize(conn)
    @values = {}
    rows = conn.exec_params("SELECT name, value FROM site_settings WHERE name = ANY($1::text[])", ["{#{NAMES.join(',')}}"])
    rows.ntuples.times { |i| @values[rows.getvalue(i, 0).to_s] = rows.getvalue(i, 1).to_s }
  end

  def hidden_visible?
    enabled?("granular_anonymous_and_logged_in_groups_permissions", false) && value("hidden_post_visible_groups", "14").split("|").include?("4")
  end
end

class NativeReactions
  # Post.find's undeleted scope, followed by Guardian.ensure_can_see!(post).
  # Direct unlisted topics are allowed. Hidden posts are NOT the topic stream's
  # placeholder policy: Guardian denies them unless anonymous group4 may see.
  POST_QUERY = <<~SQL
    SELECT p.id,
      (t.id IS NOT NULL AND t.deleted_at IS NULL
       AND t.archetype <> 'private_message' AND c.id IS NOT NULL
       AND c.read_restricted IS NOT TRUE
       AND NOT EXISTS (SELECT 1 FROM shared_drafts d WHERE d.topic_id=t.id)
       AND p.post_type IN (1,2,3) AND (p.hidden IS NOT TRUE OR $2::boolean)) AS allowed
    FROM posts p LEFT JOIN topics t ON t.id=p.topic_id
      LEFT JOIN categories c ON c.id=t.category_id
    WHERE p.id=$1::integer AND p.deleted_at IS NULL
  SQL
  # PostReactionsQuery#reactions_select_sql, anonymous branch: no ignored users.
  REACTIONS_SELECT = <<~SQL
    SELECT u.id, u.username, u.name, u.uploaded_avatar_id,
      dr.reaction_value AS reaction, drru.created_at
    FROM discourse_reactions_reaction_users drru
    INNER JOIN discourse_reactions_reactions dr ON dr.id=drru.reaction_id
    INNER JOIN users u ON u.id=drru.user_id
    WHERE drru.post_id=$1::integer
  SQL
  # strict_filter_reaction_likes_sql suppresses ANY reaction, not only enabled
  # values/counts. Deliberately no valid-reactions/count/active/profile filters.
  SHADOW_LIKE_FILTER = <<~SQL
    post_actions.post_action_type_id=2 AND post_actions.deleted_at IS NULL
    AND NOT EXISTS (
      SELECT 1 FROM discourse_reactions_reaction_users
      WHERE discourse_reactions_reaction_users.user_id=post_actions.user_id
        AND discourse_reactions_reaction_users.post_id=post_actions.post_id
    )
  SQL
  LIKES_SELECT = <<~SQL
    SELECT u.id, u.username, u.name, u.uploaded_avatar_id,
      $2::text AS reaction, post_actions.created_at
    FROM post_actions INNER JOIN users u ON u.id=post_actions.user_id
    WHERE post_actions.post_id=$1::integer AND (#{SHADOW_LIKE_FILTER})
  SQL
  # Typed otherwise-unused binds keep one native execution API for all branches.
  PARAMS = "WITH reaction_params AS (SELECT $1::integer, $2::text, $3::text, $4::integer, $5::bigint) "

  def self.rows_sql(filter, main)
    selection = if !NativeReactionsRequest.blank?(filter) && filter != main
      REACTIONS_SELECT + " AND dr.reaction_value=$3::text"
    elsif filter == main
      LIKES_SELECT
    else
      "SELECT * FROM (#{REACTIONS_SELECT} UNION ALL #{LIKES_SELECT}) combined"
    end
    PARAMS + "SELECT row_to_json(r) FROM (#{selection} ORDER BY created_at ASC LIMIT $4::integer OFFSET $5::bigint) r"
  end

  def self.total_sql(filter, main)
    reactions = "SELECT count(*) FROM discourse_reactions_reaction_users WHERE post_id=$1::integer"
    if !NativeReactionsRequest.blank?(filter) && filter != main
      reactions = "SELECT count(*) FROM discourse_reactions_reaction_users drru INNER JOIN discourse_reactions_reactions dr ON dr.id=drru.reaction_id WHERE drru.post_id=$1::integer AND dr.reaction_value=$3::text"
    end
    likes = "SELECT count(*) FROM post_actions WHERE post_id=$1::integer AND (#{SHADOW_LIKE_FILTER})"
    expression = if !NativeReactionsRequest.blank?(filter) && filter != main
      "(#{reactions})"
    elsif filter == main
      "(#{likes})"
    else
      "(#{reactions}) + (#{likes})"
    end
    PARAMS + "SELECT #{expression}"
  end

  def initialize(conn)
    @conn = conn
  end

  # Stable status contract; Rails error templates/envelopes aren't reimplemented.
  def self.access_status(settings, found, allowed)
    return 403 if settings.enabled?("login_required", false)
    return 404 unless settings.enabled?("discourse_reactions_enabled", true)
    return 404 unless found
    allowed ? 200 : 403
  end

  def self.serialize_user(row, settings)
    raise "unsupported reactions default avatars" unless settings.value("default_avatars", "").empty?
    # Source uses User.avatar_template(username, upload), NOT the instance method
    # which gives the system user a special logo. Omit ID for that adapter call.
    avatar_user = { "username" => row["username"], "uploaded_avatar_id" => row["uploaded_avatar_id"] }
    result = { "username" => row["username"] }
    result["name"] = row["name"] if settings.enabled?("enable_names", true)
    result["avatar_template"] = NativeUsers.avatar_template(avatar_user, settings)
    result["id"] = row["id"]
    result["reaction"] = row["reaction"]
    result
  end

  def call(request)
    @conn.exec("BEGIN READ ONLY ISOLATION LEVEL REPEATABLE READ")
    begin
      settings = NativeReactionsSettings.new(@conn)
      status = self.class.access_status(settings, true, true)
      return [status, JSON.generate({ "error" => "plugin disabled or anonymous access denied" })] unless status == 200
      post = @conn.exec_params(POST_QUERY, [request.id.to_s, settings.hidden_visible? ? "true" : "false"])
      status = self.class.access_status(settings, post.ntuples > 0, post.ntuples > 0 && post.getvalue(0, 1).to_s == "t")
      return [status, JSON.generate({ "error" => "post not found or inaccessible" })] unless status == 200
      main = settings.value("discourse_reactions_reaction_for_like", "heart").gsub("-", "")
      binds = [request.id.to_s, main, request.reaction_filter, request.limit.to_s, (request.page * request.limit).to_s]
      rows = @conn.exec_params(self.class.rows_sql(request.reaction_filter, main), binds)
      users = []
      rows.ntuples.times { |i| users << self.class.serialize_user(JSON.parse(rows.getvalue(i, 0).to_s), settings) }
      total = @conn.exec_params(self.class.total_sql(request.reaction_filter, main), binds).getvalue(0, 0).to_s.to_i
      [200, JSON.generate({ "users" => users, "total_rows" => total })]
    ensure
      @conn.exec("ROLLBACK")
    end
  end
end

# frozen_string_literal: true
require "json"
require "socket"
require_relative "../reference/native_site"
require_relative "valkey"

# Selected ApplicationLayoutPreloader guest paths, evaluated from live read-only
# data. Theme/plugin HTML and overrides are deliberately not evaluated; see GAPS.
class NativePreloads
  # Topic#banner reads ordered_posts.first (Post's deleted-row scope applies).
  # Keep this SELECT available to typed read-only CTE security fixtures.
  BANNER_QUERY = <<~SQL
    SELECT row_to_json(r) FROM (
      SELECT t.id AS key, p.cooked AS html, '/t/' || t.slug || '/' || t.id AS url
      FROM topics t LEFT JOIN categories c ON c.id = t.category_id
      JOIN LATERAL (
        SELECT cooked FROM posts
        WHERE topic_id = t.id AND deleted_at IS NULL
        ORDER BY post_number ASC LIMIT 1
      ) p ON true
      WHERE t.archetype = 'banner' AND t.deleted_at IS NULL
        AND (c.id IS NULL OR NOT c.read_restricted)
      ORDER BY t.id LIMIT 1
    ) r
  SQL

  def initialize(conn)
    @conn = conn
  end

  def call(topic_list)
    @conn.exec("BEGIN READ ONLY ISOLATION LEVEL REPEATABLE READ")
    begin
      settings = NativeReference.client_settings_json(@conn)
      site = NativeReference.site_json(@conn)
      # No remote emoji assets are silently fabricated. Native upload serving
      # and custom-emoji ACLs must be extracted before accepting nonempty data.
      raise "custom emoji preload not extracted" if @conn.exec("SELECT count(*) FROM custom_emojis").getvalue(0, 0).to_s.to_i > 0
      banners = @conn.exec(BANNER_QUERY)
      banner = banners.ntuples == 0 ? "{}" : banners.getvalue(0, 0).to_s
      readonly, staff_only = read_modes
      result = {
        "site" => site, "siteSettings" => settings,
        "themeSiteSettingOverrides" => "{}", "customHTML" => "{}",
        "banner" => banner, "customEmoji" => "[]",
        "isReadOnly" => JSON.generate(readonly), "isStaffWritesOnly" => JSON.generate(staff_only),
        "activatedThemes" => "{}", "upcomingChanges" => "{}", "topic_list" => topic_list,
      }
      @conn.exec("COMMIT")
      result
    rescue
      @conn.exec("ROLLBACK")
      raise
    end
  end

  # DiscourseRedis prefixes mode keys with the logical current_db (`default`).
  # GET/EXISTS only, no cache writes, subscriptions or background tasks.
  def read_modes
    redis = NativeValkey.new
    begin
      keys = %w[readonly_mode readonly_mode:postgres readonly_mode:user readonly_mode:postgres_force]
      readonly = redis.command(["EXISTS"] + keys.map { |key| "#{NativeValkey::SITE_ID}:#{key}" }).to_i > 0
      staff = redis.command(["EXISTS", "#{NativeValkey::SITE_ID}:readonly_mode:staff_writes_only"]).to_i > 0
      timestamp = redis.command(["GET", "#{NativeValkey::SITE_ID}:postgres:last_readonly"])
      readonly = true if timestamp && timestamp.to_i > Time.now.to_i - 15
      [readonly || staff, !readonly && staff]
    ensure
      redis.close
    end
  end
end

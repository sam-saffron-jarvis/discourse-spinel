# frozen_string_literal: true
# Runtime adapter for the anonymous browser bootstrap contract. It is not Rails.
# It deliberately emits a source-derived subset. Unsupported dynamic Rails
# callbacks, policy and translations are documented in site-contract.md.
require "json"

module NativeReference
  SOURCE_REVISION = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"

  # Values and client flags extracted from SiteSetting's source contract. Never
  # expand this allowlist to all site_settings rows: DB rows may contain secrets.
  CONTRACT = JSON.parse(File.read(File.join(__dir__, "client-settings-contract.json"))).freeze
  CLIENT_SETTINGS = CONTRACT.fetch("settings").to_h do |entry|
    [entry.fetch("name"), [entry["default"], entry.fetch("type").to_sym, entry]]
  end.freeze

  TRUST_LEVELS = { "newuser" => 0, "basic" => 1, "member" => 2, "regular" => 3, "leader" => 4 }.freeze
  POST_TYPES = { "regular" => 1, "moderator_action" => 2, "small_action" => 3, "whisper" => 4 }.freeze
  ARCHETYPES = [
    { "id" => "regular", "name" => "Regular Topic", "options" => [] },
    { "id" => "banner", "name" => "Banner Topic", "options" => [] },
  ].freeze
  # Notification enum is maintained in Notification.types; source-derived values.
  NOTIFICATION_TYPES = {
    "mentioned" => 1, "replied" => 2, "quoted" => 3, "edited" => 4,
    "liked" => 5, "private_message" => 6, "invited_to_private_message" => 7,
    "invitee_accepted" => 8, "posted" => 9, "moved_post" => 10, "linked" => 11,
    "granted_badge" => 12, "invited_to_topic" => 13, "custom" => 14,
    "group_mentioned" => 15, "group_message_summary" => 16, "watching_first_post" => 17,
    "topic_reminder" => 18, "liked_consolidated" => 19, "post_approved" => 20,
    "code_review_commit_approved" => 21, "membership_request_accepted" => 22,
    "membership_request_consolidated" => 23, "bookmark_reminder" => 24,
    "reaction" => 25, "votes_released" => 26, "event_reminder" => 27,
    "event_invitation" => 28, "chat_mention" => 29, "chat_message" => 30,
    "chat_invitation" => 31, "chat_group_mention" => 32, "chat_quoted" => 33,
    "assigned" => 34, "question_answer_user_commented" => 35,
    "watching_category_or_tag" => 36, "new_features" => 37, "admin_problems" => 38,
    "linked_consolidated" => 39, "chat_watched_thread" => 40,
    "upcoming_change_available" => 41, "upcoming_change_automatically_promoted" => 42,
    "boost" => 43, "suggested_edit_created" => 44, "suggested_edit_accepted" => 45,
    "following" => 800, "following_created_topic" => 801, "following_replied" => 802,
    "circles_activity" => 900, "live_invitation" => 1000,
  }.freeze

  # Core and task-enabled Chat HashtagAutocompleteService source projection.
  # Values are source constants from CategoryHashtagDataSource, TagHashtagDataSource,
  # and Chat::ChannelHashtagDataSource. Arbitrary plugin registry additions are not
  # available to this standalone runtime and remain unsupported.
  CORE_HASHTAG_ICONS = { "category" => "folder", "tag" => "tag", "channel" => "comment" }.freeze
  CHAT_PUBLIC_CHANNELS_SETTING = "enable_public_channels".freeze

  def self.hashtag_icons(conn, settings)
    icons = { "category" => CORE_HASHTAG_ICONS.fetch("category") }
    icons["tag"] = CORE_HASHTAG_ICONS.fetch("tag") if settings.fetch("tagging_enabled")
    rows = conn.exec_params("SELECT value FROM site_settings WHERE name = $1", [CHAT_PUBLIC_CHANNELS_SETTING])
    # Chat plugin's pinned config default is true; an explicit DB override wins.
    chat_public_channels = rows.ntuples.zero? || %w[t true 1].include?(rows.getvalue(0, 0).to_s)
    icons["channel"] = CORE_HASHTAG_ICONS.fetch("channel") if chat_public_channels
    icons
  end

  def self.site_json(conn)
    settings = read_client_settings(conn)
    raise "unsupported locale" unless settings["default_locale"] == "en"
    raise "login-required site is unsupported" if settings["login_required"]
    categories = visible_categories(conn)
    JSON.generate({
      "default_archetype" => "regular",
      "notification_types" => NOTIFICATION_TYPES,
      "post_types" => POST_TYPES,
      "trust_levels" => TRUST_LEVELS,
      "filters" => %w[latest unread new unseen top read posted bookmarks hot votes],
      "anonymous_list_filters" => %w[latest top hot votes],
      "periods" => %w[all yearly quarterly monthly weekly daily],
      "top_menu_items" => %w[latest unread new unseen top read posted bookmarks hot categories votes],
      "anonymous_top_menu_items" => %w[latest top categories hot categories top votes],
      "can_create_tag" => false,
      "can_search" => true,
      "can_tag_topics" => false,
      "can_tag_pms" => false,
      "hashtag_icons" => hashtag_icons(conn, settings),
      "categories" => categories,
      "archetypes" => ARCHETYPES,
    })
  end

  # Rails SiteSetting.client_settings_json behavior, restricted to the explicitly
  # safe client allowlist above. Values are live DB overrides; unknown rows never
  # enter output. The caller must already have enabled a PG read-only transaction.
  def self.client_settings_json(conn)
    JSON.generate(read_client_settings(conn))
  end

  def self.read_client_settings(conn)
    names = CLIENT_SETTINGS.keys + ["promote_upcoming_changes_on_status"]
    rows = conn.exec_params("SELECT name, value FROM site_settings WHERE name = ANY($1::text[])", ["{#{names.join(',')}}"])
    defaults = CLIENT_SETTINGS.to_h { |name, (default, type, _metadata)| [name, cast(default, type)] }
    stored_settings = {}
    rows.ntuples.times do |i|
      name = rows.getvalue(i, 0).to_s
      if name == "promote_upcoming_changes_on_status"
        stored_settings[name] = rows.getvalue(i, 1).to_s
        next
      end
      next unless CLIENT_SETTINGS.key?(name)
      value = cast(rows.getvalue(i, 1).to_s, CLIENT_SETTINGS[name][1])
      defaults[name] = value
      stored_settings[name] = value
    end
    apply_upcoming_change_default_overrides!(defaults, stored_settings)
    upload_entries = defaults.select { |name, _value| CLIENT_SETTINGS[name][1] == :upload }
    upload_ids = upload_entries.values.map(&:to_i).uniq
    unless upload_ids.empty?
      uploads = conn.exec_params("SELECT id, url FROM uploads WHERE id = ANY($1::bigint[])", ["{#{upload_ids.join(',')}}"])
      upload_urls = {}
      uploads.ntuples.times { |i| upload_urls[uploads.getvalue(i, 0).to_i] = uploads.getvalue(i, 1).to_s }
      upload_entries.each_key { |name| defaults[name] = upload_urls.fetch(defaults[name].to_i, "") }
    end
    defaults
  end

  def self.apply_upcoming_change_default_overrides!(values, stored_settings)
    status_rank = { "conceptual" => -100, "experimental" => 0, "alpha" => 100,
                    "beta" => 200, "stable" => 300, "permanent" => 500, "never" => 9999 }
    promote_status = stored_settings.fetch("promote_upcoming_changes_on_status", CONTRACT["promote_upcoming_changes_on_status_default"] || "beta")
    raise "unsupported upcoming-change promotion threshold" unless %w[experimental alpha beta stable never].include?(promote_status)
    CLIENT_SETTINGS.each do |name, (default, _type, metadata)|
      change = metadata["upcoming_change"]
      next unless change && !stored_settings.key?(name)
      status = change["status"].to_s
      values[name] = status == "permanent" ||
        status_rank.fetch(status, -100) >= status_rank.fetch(promote_status.to_s, 200) ? true : default
    end
    CLIENT_SETTINGS.each do |name, (_default, type, metadata)|
      override = metadata["upcoming_change_default_override"]
      next unless override && !stored_settings.key?(name)
      change_name = override.fetch("upcoming_change")
      next unless CLIENT_SETTINGS.key?(change_name)
      values[name] = cast(override.fetch("new_default"), type) if values[change_name] == true
    end
    values
  end
  private_class_method :apply_upcoming_change_default_overrides!

  def self.cast(value, type)
    case type
    when :boolean, :bool then value == true || value.to_s == "t" || value.to_s == "true"
    when :integer, :file_size_restriction then Integer(value.to_s, 10)
    when :float then Float(value.to_s)
    when :category_list, :tag_list, :list, :group_list
      value.to_s
    when :uploaded_image_list
      raise "nonempty uploaded-image list not extracted" unless value.nil? || value.to_s.empty?
      []
    when :json_schema, :objects
      value.nil? || value.to_s.empty? ? value : JSON.parse(value.to_s)
    else value.nil? ? nil : value.to_s
    end
  end
  private_class_method :cast

  def self.visible_categories(conn)
    rows = conn.exec(<<~SQL)
      SELECT c.id, c.name, c.color, c.text_color, c.slug, c.parent_category_id, c.position,
             c.read_restricted,
             EXISTS (SELECT 1 FROM categories child WHERE child.parent_category_id = c.id) AS has_children
      FROM categories c
      WHERE c.read_restricted = false
      ORDER BY c.position, c.id
    SQL
    categories = []
    rows.ntuples.times do |i|
      categories << {
        "id" => rows.getvalue(i, 0).to_i, "name" => rows.getvalue(i, 1),
        "color" => rows.getvalue(i, 2), "text_color" => rows.getvalue(i, 3),
        "slug" => rows.getvalue(i, 4), "parent_category_id" => nullable_integer(rows.getvalue(i, 5)),
        "position" => rows.getvalue(i, 6).to_i, "read_restricted" => false,
        "has_children" => rows.getvalue(i, 8) == "t",
      }
    end
    visible_ids = categories.map { |c| c["id"] }
    categories = categories.reject { |c| c["parent_category_id"] && !visible_ids.include?(c["parent_category_id"]) }
    parent_ids = categories.map { |c| c["parent_category_id"] }.compact
    categories.each do |category|
      category.delete("parent_category_id") if category["parent_category_id"].nil?
      category["has_children"] = parent_ids.include?(category["id"])
    end
    categories
  end
  private_class_method :visible_categories

  def self.nullable_integer(value)
    value.nil? ? nil : value.to_i
  end
  private_class_method :nullable_integer
end

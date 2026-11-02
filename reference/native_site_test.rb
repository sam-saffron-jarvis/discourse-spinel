# frozen_string_literal: true
require "minitest/autorun"
require "json"
require_relative "native_site"

class NativeReferenceTest < Minitest::Test
  class Result
    def initialize(rows)
      @rows = rows
    end
    def ntuples = @rows.length
    def getvalue(i, j) = @rows[i][j]
  end

  class FakeConnection
    attr_reader :queries
    def initialize(chat_setting = "t")
      @queries = []
      @chat_setting = chat_setting
    end
    def exec_params(sql, params)
      @queries << [sql, params]
      if sql.include?("SELECT value FROM site_settings")
        Result.new([[@chat_setting]])
      elsif sql.include?("FROM uploads")
        Result.new([[-5, "/images/discourse-logo-sketch.png"], [-6, "/images/discourse-logo-sketch-small.png"]])
      else
        Result.new([["default_locale", "en"], ["login_required", "f"], ["title", "Live title"], ["smtp_password", "dont-expose"]])
      end
    end
    def exec(sql)
      @queries << [sql, []]
      Result.new([["3", "public", "abc123", "ffffff", "public", nil, "1", "f", "f"]])
    end
  end

  def test_client_settings_live_overrides_and_never_emits_unallowlisted_values
    conn = FakeConnection.new
    settings = JSON.parse(NativeReference.client_settings_json(conn))
    assert_equal "en", settings.fetch("default_locale")
    assert_equal "Live title", settings.fetch("title")
    assert_equal true, settings.fetch("discourse_reactions_enabled")
    assert_equal "heart", settings.fetch("discourse_reactions_reaction_for_like")
    assert_equal "heart", settings.fetch("discourse_reactions_like_icon")
    assert_equal false, settings.fetch("discourse_reactions_desaturated_reaction_panel")
    refute settings.key?("discourse_reactions_excluded_from_like")
    refute settings.key?("discourse_reactions_like_sync_enabled")
    assert_equal false, settings.fetch("login_required")
    assert_equal "/images/discourse-logo-sketch.png", settings.fetch("logo")
    assert_equal "/images/discourse-logo-sketch-small.png", settings.fetch("logo_small")
    assert_equal true, settings.fetch("enable_unified_new")
    assert_equal "latest|new|hot|categories", settings.fetch("top_menu")
    refute settings.key?("smtp_password")
    assert_equal NativeReference::CLIENT_SETTINGS.keys.sort, settings.keys.sort
    assert_match(/name = ANY\(\$1::text\[\]\)/, conn.queries.first.first)
    assert_equal "{#{(NativeReference::CLIENT_SETTINGS.keys + ['promote_upcoming_changes_on_status']).join(',')}}", conn.queries.first.last.first
  end

  def test_site_contract_excludes_restricted_categories_and_has_browser_fields
    json = JSON.parse(NativeReference.site_json(FakeConnection.new))
    assert_equal %w[regular banner], json.fetch("archetypes").map { |a| a.fetch("id") }
    assert_equal "Regular Topic", json.fetch("archetypes").first.fetch("name")
    assert_equal ["public"], json.fetch("categories").map { |c| c.fetch("name") }
    assert_match(/WHERE c.read_restricted = false/, FakeConnection.new.tap { |conn| NativeReference.site_json(conn) }.queries.map(&:first).find { |sql| sql.include?("FROM categories") })
    assert_equal({ "newuser" => 0, "basic" => 1, "member" => 2, "regular" => 3, "leader" => 4 }, json.fetch("trust_levels"))
    assert_equal 1, json.fetch("post_types").fetch("regular")
    assert_equal 2, json.fetch("notification_types").fetch("replied")
    assert_equal false, json.fetch("can_create_tag")
    assert_equal true, json.fetch("can_search")
    assert_equal %w[latest unread new unseen top read posted bookmarks hot votes], json.fetch("filters")
    assert_equal %w[latest top hot votes], json.fetch("anonymous_list_filters")
    assert_equal %w[all yearly quarterly monthly weekly daily], json.fetch("periods")
    assert_equal %w[latest unread new unseen top read posted bookmarks hot categories votes], json.fetch("top_menu_items")
    assert_equal %w[latest top categories hot categories top votes], json.fetch("anonymous_top_menu_items")
    assert_equal({ "category" => "folder", "tag" => "tag", "channel" => "comment" }, json.fetch("hashtag_icons"))
  end

  def test_hashtag_icons_follow_enabled_source_registry
    conn = FakeConnection.new
    assert_equal({ "category" => "folder", "tag" => "tag", "channel" => "comment" }, NativeReference.hashtag_icons(conn, "tagging_enabled" => true))
    assert_equal({ "category" => "folder", "channel" => "comment" }, NativeReference.hashtag_icons(conn, "tagging_enabled" => false))
    disabled_conn = FakeConnection.new("f")
    assert_equal({ "category" => "folder", "tag" => "tag" }, NativeReference.hashtag_icons(disabled_conn, "tagging_enabled" => true))
    query, params = conn.queries.last
    assert_match(/SELECT value FROM site_settings WHERE name = \$1/, query)
    assert_equal ["enable_public_channels"], params
  end

  def test_metadata_is_pinned_and_client_settings_are_bounded
    assert_equal "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8", NativeReference::SOURCE_REVISION
    refute NativeReference::CLIENT_SETTINGS.key?("smtp_password")
    refute NativeReference::CLIENT_SETTINGS.key?("notification_email")
    %w[avatar_sizes anon_polling_interval background_polling_interval navigation_menu].each do |name|
      assert NativeReference::CLIENT_SETTINGS.key?(name), "missing source client setting #{name}"
    end
  end
end

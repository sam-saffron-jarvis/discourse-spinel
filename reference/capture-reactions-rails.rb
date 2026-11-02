# frozen_string_literal: true

# Run from the Discourse checkout with `bin/rails runner ../minimal/reference/capture-reactions-rails.rb`.
# This is a read-only live Rails/plugin oracle. It never starts a service or mutates SiteSettings.
require "json"
require "uri"

expected_database_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
expected_valkey_url = "redis://127.0.0.1:6399/0"
abort "DATABASE_URL must be #{expected_database_url}" unless ENV["DATABASE_URL"] == expected_database_url
abort "REDIS_URL must be #{expected_valkey_url}" unless ENV["REDIS_URL"] == expected_valkey_url

count_text = ENV.fetch("REACTIONS_ORACLE_COUNT", "4")
abort "REACTIONS_ORACLE_COUNT must be 3, 4, or 5" unless count_text.match?(/\A[345]\z/)
sample_size = count_text.to_i

connection = ActiveRecord::Base.connection
report = nil
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")

  guardian = Guardian.new(nil)
  visible_posts = []
  denied_post_ids = []
  checked_count = 0
  # Walk actual persisted posts, asking the source Guardian for each. No visibility
  # approximation is used to admit a selected post; record denied live examples too.
  activity_ids = (DiscourseReactions::ReactionUser.distinct.pluck(:post_id) +
    PostAction.where(post_action_type_id: PostActionType::LIKE_POST_ACTION_ID, deleted_at: nil).distinct.pluck(:post_id)).compact.uniq
  global_live_counts = {
    "reactions" => DiscourseReactions::Reaction.count,
    "reaction_users" => DiscourseReactions::ReactionUser.count,
    "likes" => PostAction.where(post_action_type_id: PostActionType::LIKE_POST_ACTION_ID, deleted_at: nil).count,
  }
  # Prefer actual activity where any exists; still admit it ONLY with Guardian.
  candidates = (Post.unscoped.where(deleted_at: nil, id: activity_ids).order(id: :desc).to_a +
    Post.unscoped.where(deleted_at: nil).order(id: :desc).limit(2_000).to_a).uniq(&:id)
  candidates.each do |post|
    checked_count += 1
    if guardian.can_see?(post)
      visible_posts << post if visible_posts.length < sample_size
    else
      denied_post_ids << post.id if denied_post_ids.length < 25
    end
  end
  abort "fewer than #{sample_size} visible live posts found in first #{checked_count} candidates" if visible_posts.length < sample_size

  main_reaction = DiscourseReactions::Reaction.main_reaction_id
  enabled = SiteSetting.discourse_reactions_enabled
  sessions = {}
  session_for = lambda do |accept|
    sessions[accept] ||= begin
      session = ActionDispatch::Integration::Session.new(Rails.application)
      session.host! "localhost"
      session
    end
  end
  request = lambda do |label, path, accept: nil, xhr: false|
    headers = {}
    headers["HTTP_ACCEPT"] = accept if accept
    headers["HTTP_X_REQUESTED_WITH"] = "XMLHttpRequest" if xhr
    session = session_for.call(accept || "(none)")
    session.get(path, headers: headers)
    status = session.response.status
    entry = { "case" => label, "path" => path, "accept" => accept, "xhr" => xhr, "status" => status }
    if status >= 400 && (error = session.request.env["action_dispatch.exception"])
      entry["source_exception"] = { "class" => error.class.name, "message" => error.message,
        "backtrace" => error.backtrace.first(8) }
    end
    if status >= 200 && status < 300
      begin
        payload = JSON.parse(session.response.body)
        entry["users"] = payload["users"] if payload.key?("users")
        entry["total_rows"] = payload["total_rows"] if payload.key?("total_rows")
        entry["json_keys"] = payload.keys.sort unless payload.key?("users")
      rescue JSON::ParserError
        entry["body_parse_error"] = true
      end
    end
    entry
  end

  cases = []
  rows = visible_posts.map do |post|
    cases << request.call("json_suffix", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json")
    cases << request.call("extensionless_json_accept", "/discourse-reactions/posts/#{post.id}/reactions-users-list", accept: "application/json")
    cases << request.call("extensionless_xhr", "/discourse-reactions/posts/#{post.id}/reactions-users-list", xhr: true)
    cases << request.call("extensionless_plain_accept", "/discourse-reactions/posts/#{post.id}/reactions-users-list")
    cases << request.call("malformed_scalar_page_limit", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?page=bogus&limit=bogus")
    cases << request.call("negative_page_zero_limit", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?page=-3&limit=0")
    cases << request.call("page_one_limit_one", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?page=1&limit=1")
    cases << request.call("limit_above_maximum", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?limit=999")
    cases << request.call("blank_reaction_filter", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?reaction_value=")
    cases << request.call("whitespace_reaction_filter", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?reaction_value=%20%20")
    cases << request.call("main_reaction_filter", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?reaction_value=#{URI.encode_www_form_component(main_reaction.to_s)}")
    cases << request.call("unknown_reaction_filter", "/discourse-reactions/posts/#{post.id}/reactions-users-list.json?reaction_value=oracle-unknown-reaction")

    {
      "post_id" => post.id,
      "topic_id" => post.topic_id,
      "guardian_can_see" => true,
      "reaction_rows" => DiscourseReactions::Reaction.where(post_id: post.id).count,
      "reaction_user_rows" => DiscourseReactions::ReactionUser.joins(:reaction).where(discourse_reactions_reactions: { post_id: post.id }).count,
      "like_rows" => PostAction.where(post_id: post.id, post_action_type_id: PostActionType::LIKE_POST_ACTION_ID, deleted_at: nil).count,
    }
  end

  sample_counts = {
    "reactions" => rows.sum { |row| row["reaction_rows"] },
    "reaction_users" => rows.sum { |row| row["reaction_user_rows"] },
    "likes" => rows.sum { |row| row["like_rows"] },
  }

  cases << request.call("underscored_page_unicode_blank_limit", "/discourse-reactions/posts/#{visible_posts.first.id}/reactions-users-list.json?page=1_02tail&limit=%C2%A0")
  cases << request.call("unicode_blank_reaction_filter", "/discourse-reactions/posts/#{visible_posts.first.id}/reactions-users-list.json?reaction_value=%C2%A0")
  zero_path = "/discourse-reactions/posts/0/reactions-users-list.json"
  cases << request.call("absent_post_zero", zero_path)

  # If any source-visible candidate was denied, exercise the real endpoint too.
  denied_probe = nil
  if denied_post_ids.any?
    denied_probe = request.call("guardian_denied_live_post", "/discourse-reactions/posts/#{denied_post_ids.first}/reactions-users-list.json")
  end

  # Synthetic callback fixture: inject only Plugin::Instance#enabled? for one
  # anonymous request, then restore the real method even if the request raises.
  # The live SiteSetting and live request results are never altered by this fixture.
  reactions_plugin = Discourse.plugins_by_name.fetch("discourse-reactions")
  plugin_singleton = reactions_plugin.singleton_class
  had_singleton_enabled =
    (plugin_singleton.instance_methods(false) + plugin_singleton.private_instance_methods(false) +
      plugin_singleton.protected_instance_methods(false)).include?(:enabled?)
  method_visibility = if plugin_singleton.private_instance_methods(false).include?(:enabled?)
    :private
  elsif plugin_singleton.protected_instance_methods(false).include?(:enabled?)
    :protected
  else
    :public
  end
  saved_enabled_method = plugin_singleton.instance_method(:enabled?) if had_singleton_enabled
  setting_before_fixture = SiteSetting.discourse_reactions_enabled
  abort "live reactions plugin is unexpectedly disabled" unless enabled && reactions_plugin.enabled?
  synthetic_disabled_request = nil
  begin
    plugin_singleton.define_method(:enabled?) { false }
    target_post_id = visible_posts.first.id
    synthetic_disabled_request = request.call(
      "synthetic_disabled_plugin_requires_plugin_callback",
      "/discourse-reactions/posts/#{target_post_id}/reactions-users-list.json",
    )
  ensure
    if had_singleton_enabled
      plugin_singleton.define_method(:enabled?, saved_enabled_method)
      plugin_singleton.send(method_visibility, :enabled?)
    else
      plugin_singleton.remove_method(:enabled?) if plugin_singleton.instance_methods(false).include?(:enabled?)
    end
  end
  abort "SiteSetting changed during synthetic disabled-plugin fixture" unless
    SiteSetting.discourse_reactions_enabled == setting_before_fixture
  abort "plugin enabled? override was not restored" unless reactions_plugin.enabled? == enabled

  report = {
    "label" => "live actual Rails/plugin read-only oracle",
    "source_revision" => `git rev-parse HEAD`.strip,
    "database" => expected_database_url,
    "valkey" => expected_valkey_url,
    "read_only" => true,
    "transaction" => "READ ONLY; queries and integration requests ran inside the transaction, then it was rolled back",
    "settings" => {
      "discourse_reactions_enabled" => enabled,
      "main_reaction" => main_reaction,
      "enabled_reactions" => SiteSetting.discourse_reactions_enabled_reactions,
      "enable_names" => SiteSetting.enable_names,
    },
    "synthetic_disabled_plugin_request" => {
      "label" => "synthetic in-process dependency-injection fixture; not live settings parity",
      "source_callback" => "ApplicationController.requires_plugin raises PluginDisabled when the registered plugin instance reports !enabled?",
      "injection" => "actual discourse-reactions Plugin::Instance#enabled? returned false for this one request only; method restored in ensure",
      "site_setting_mutated" => false,
      "request" => synthetic_disabled_request,
      "expected_status" => 404,
      "callback_confirmed" => synthetic_disabled_request["status"] == 404,
    },
    "post_selection" => {
      "method" => "activity-bearing live posts first, then newest non-deleted persisted posts, admitted only by Guardian.new(nil).can_see?(post)",
      "global_live_counts" => global_live_counts,
      "visible_posts" => rows,
      "sample_live_counts" => sample_counts,
      "guardian_checked_candidates" => checked_count,
      "guardian_denied_live_post_ids_sample" => denied_post_ids,
      "guardian_denied_posts_available" => !denied_post_ids.empty?,
      "deleted_posts_available" => Post.unscoped.where.not(deleted_at: nil).exists?,
    },
    "requests" => cases,
    "denied_post_request" => denied_probe,
  }
  raise ActiveRecord::Rollback
end

puts JSON.pretty_generate(JSON.parse(ActiveSupport::JSON.encode(report)))

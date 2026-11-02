# frozen_string_literal: true

# Run from the Discourse checkout with bin/rails runner. Read-only live oracle
# for the distinct reactions-users summary action; no settings or DB writes.
require "json"
require "uri"

expected_database_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
expected_valkey_url = "redis://127.0.0.1:6399/0"
abort "DATABASE_URL must be #{expected_database_url}" unless ENV["DATABASE_URL"] == expected_database_url
abort "REDIS_URL must be #{expected_valkey_url}" unless ENV["REDIS_URL"] == expected_valkey_url

connection = ActiveRecord::Base.connection
report = nil
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")
  guardian = Guardian.new(nil)
  activity_ids = (DiscourseReactions::Reaction.distinct.pluck(:post_id) +
    DiscourseReactions::ReactionUser.distinct.pluck(:post_id) +
    PostAction.where(post_action_type_id: PostActionType::LIKE_POST_ACTION_ID, deleted_at: nil).distinct.pluck(:post_id)).compact.uniq
  candidates = (Post.unscoped.where(deleted_at: nil, id: activity_ids).order(id: :desc).to_a +
    Post.unscoped.where(deleted_at: nil).order(id: :desc).limit(2_000).to_a).uniq(&:id)
  visible = []
  denied = []
  candidates.each do |post|
    if guardian.can_see?(post)
      visible << post
    else
      denied << post
    end
  end
  abort "no visible live posts available" if visible.empty?
  enabled = SiteSetting.discourse_reactions_enabled
  plugin = Discourse.plugins_by_name.fetch("discourse-reactions")
  abort "live reactions plugin unexpectedly disabled" unless enabled && plugin.enabled?
  main = DiscourseReactions::Reaction.main_reaction_id

  session = ActionDispatch::Integration::Session.new(Rails.application)
  session.host! "localhost"
  request = lambda do |label, method, path, headers = {}|
    session.process(method, path, headers: headers)
    response = session.response
    entry = { "case" => label, "method" => method, "path" => path, "status" => response.status }
    if response.status.between?(200, 299)
      begin
        payload = JSON.parse(response.body)
        entry["reaction_users"] = payload["reaction_users"] if payload.key?("reaction_users")
        entry["json_keys"] = payload.keys.sort unless payload.key?("reaction_users")
      rescue JSON::ParserError
        entry["body_parse_error"] = true
      end
    end
    if response.status >= 400 && (exception = session.request.env["action_dispatch.exception"])
      entry["source_exception"] = { "class" => exception.class.name, "message" => exception.message }
    end
    entry
  end
  cases = []
  sample = visible.first(4)
  sample.each do |post|
    path = "/discourse-reactions/posts/#{post.id}/reactions-users.json"
    cases << request.call("json_no_filter", "GET", path)
    ["", "%20%20", URI.encode_www_form_component(main.to_s), "oracle-unknown-reaction"].each_with_index do |filter, i|
      cases << request.call(["empty_filter", "whitespace_filter", "main_filter", "unknown_filter"][i], "GET", "#{path}?reaction_value=#{filter}")
    end
  end
  pid = sample.first.id
  path = "/discourse-reactions/posts/#{pid}/reactions-users"
  cases << request.call("extensionless_json_accept", "GET", path, "HTTP_ACCEPT" => "application/json")
  cases << request.call("extensionless_xhr", "GET", path, "HTTP_X_REQUESTED_WITH" => "XMLHttpRequest")
  cases << request.call("extensionless_plain_html", "GET", path)
  cases << request.call("malformed_scalar", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?reaction_value[]=heart")
  cases << request.call("duplicate_filter", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?reaction_value=a&reaction_value=b")
  cases << request.call("unknown_parameter", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?unexpected=1")
  cases << request.call("malformed_id", "GET", "/discourse-reactions/posts/01/reactions-users.json")
  cases << request.call("malformed_post_id", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?post_id=1")
  cases << request.call("malformed_page", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?page=1")
  cases << request.call("malformed_limit", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?limit=1")
  cases << request.call("oversized_query", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json?x=#{'x' * 2050}")
  cases << request.call("missing_post", "GET", "/discourse-reactions/posts/0/reactions-users.json")
  cases << request.call("negative_id", "GET", "/discourse-reactions/posts/-1/reactions-users.json")
  cases << request.call("above_max_id", "GET", "/discourse-reactions/posts/2147483648/reactions-users.json")
  %w[POST PUT PATCH DELETE OPTIONS HEAD].each do |verb|
    cases << request.call("unsupported_#{verb.downcase}", verb, "/discourse-reactions/posts/#{pid}/reactions-users.json")
  end
  denied_by_reason = denied.group_by do |post|
    if post.hidden
      "hidden"
    elsif post.topic&.archetype == "private_message"
      "private_topic"
    else
      "guardian_denied"
    end
  end
  denied_sample = denied_by_reason.keys.sort.flat_map { |reason| denied_by_reason.fetch(reason).first(1).map { |post| [post, reason] } }
  denied_sample.concat(denied.reject { |post| denied_sample.any? { |sample_post, _| sample_post.id == post.id } }.first([0, 8 - denied_sample.length].max).map { |post| [post, "guardian_denied"] })
  denied_sample = denied_sample.first(8).map { |post, reason| { "post_id" => post.id, "reason" => reason } }
  denied_sample.each do |row|
    cases << request.call("denied_#{row['reason']}", "GET", "/discourse-reactions/posts/#{row['post_id']}/reactions-users.json")
  end
  deleted_sample = Post.unscoped.where.not(deleted_at: nil).order(id: :desc).limit(4).map do |post|
    row = { "post_id" => post.id, "reason" => "deleted" }
    cases << request.call("deleted_post", "GET", "/discourse-reactions/posts/#{post.id}/reactions-users.json")
    row
  end
  cases << request.call("authorization_header", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json", "HTTP_AUTHORIZATION" => "Bearer oracle-secret")
  cases << request.call("api_key_header", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json", "HTTP_API_KEY" => "oracle-secret")
  cases << request.call("session_cookie", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json", "HTTP_COOKIE" => "_forum_session=oracle-secret")

  # Disabled-plugin callback is process-local and restored in ensure; no SiteSetting write.
  singleton = plugin.singleton_class
  singleton_methods = singleton.instance_methods(false) + singleton.private_instance_methods(false) + singleton.protected_instance_methods(false)
  had = singleton_methods.include?(:enabled?)
  visibility = if singleton.private_instance_methods(false).include?(:enabled?)
    :private
  elsif singleton.protected_instance_methods(false).include?(:enabled?)
    :protected
  else
    :public
  end
  previous = singleton.instance_method(:enabled?) if had
  setting_before_fixture = SiteSetting.discourse_reactions_enabled
  disabled_request = nil
  begin
    singleton.define_method(:enabled?) { false }
    disabled_request = request.call("synthetic_disabled_plugin", "GET", "/discourse-reactions/posts/#{pid}/reactions-users.json")
  ensure
    if had
      singleton.define_method(:enabled?, previous)
      singleton.send(visibility, :enabled?)
    elsif singleton.instance_methods(false).include?(:enabled?)
      singleton.remove_method(:enabled?)
    end
  end
  abort "live SiteSetting changed during disabled-plugin fixture" unless SiteSetting.discourse_reactions_enabled == setting_before_fixture
  abort "plugin enabled? callback not restored" unless plugin.enabled? == enabled

  live_counts = {
    "reactions" => DiscourseReactions::Reaction.count,
    "reaction_users" => DiscourseReactions::ReactionUser.count,
    "likes" => PostAction.where(post_action_type_id: PostActionType::LIKE_POST_ACTION_ID, deleted_at: nil).count,
  }
  report = {
    "label" => "actual Rails/plugin read-only live HTTP oracle",
    "source_revision" => `git rev-parse HEAD`.strip,
    "database" => expected_database_url, "valkey" => expected_valkey_url,
    "read_only" => true,
    "transaction" => "transaction explicitly READ ONLY and rolled back",
    "settings" => { "reactions_enabled" => enabled, "main_reaction" => main,
      "valid_reactions" => DiscourseReactions::Reaction.valid_reactions.to_a },
    "visibility" => { "sample_post_ids" => sample.map(&:id), "denied_posts" => denied_sample,
      "deleted_posts" => deleted_sample, "guardian_checked" => candidates.length },
    "live_counts" => live_counts,
    "synthetic_disabled_plugin_request" => { "request" => disabled_request,
      "site_setting_before" => setting_before_fixture,
      "site_setting_after" => SiteSetting.discourse_reactions_enabled,
      "site_setting_mutated" => SiteSetting.discourse_reactions_enabled != setting_before_fixture },
    "requests" => cases,
  }
  raise ActiveRecord::Rollback
end
puts JSON.pretty_generate(JSON.parse(ActiveSupport::JSON.encode(report)))

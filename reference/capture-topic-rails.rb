# Run from the Discourse Rails checkout with `bin/rails runner`.
# Verification only: no HTTP server, no response proxy, and no database writes.
require "json"

expected_database_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
expected_redis_url = "redis://127.0.0.1:6399/0"
abort "DATABASE_URL must be #{expected_database_url}" unless ENV["DATABASE_URL"] == expected_database_url
abort "REDIS_URL must be #{expected_redis_url}" unless ENV["REDIS_URL"] == expected_redis_url

# Explicit minimal-topic-v1 projection; deliberately not full serializer equality.
TOPIC_SERIALIZER_FIELDS = %w[
  id title posts_count created_at views reply_count like_count last_posted_at visible closed archived
  has_summary archetype slug category_id word_count deleted_at user_id pinned_globally pinned_at
  pinned_until slow_mode_seconds draft draft_key draft_sequence unpinned pinned current_post_number
  highest_post_number chunk_size bookmarked
].freeze
POST_GETTERS = {
  "id" => "id", "name" => "name", "username" => "username", "avatar_template" => "avatar_template",
  "created_at" => "created_at", "cooked" => "cooked", "post_number" => "post_number",
  "post_type" => "post_type", "posts_count" => "posts_count", "updated_at" => "updated_at",
  "reply_count" => "reply_count", "reply_to_post_number" => "reply_to_post_number",
  "quote_count" => "quote_count", "incoming_link_count" => "incoming_link_count", "reads" => "reads",
  "readers_count" => "readers_count", "score" => "score", "topic_id" => "topic_id",
  "topic_slug" => "topic_slug", "display_username" => "display_username", "primary_group_name" => "primary_group_name",
  "user_id" => "user_id", "version" => "version", "yours" => "yours", "can_edit" => "can_edit",
  "can_delete" => "can_delete", "can_recover" => "can_recover",
  "can_see_hidden_post" => "can_see_hidden_post", "can_wiki" => "can_wiki", "read" => "read",
  "action_code" => "action_code", "admin" => "admin?", "moderator" => "moderator?", "staff" => "staff?",
  "trust_level" => "trust_level", "hidden" => "hidden", "user_deleted" => "user_deleted",
  "wiki" => "wiki", "deleted_at" => "deleted_at",
}.freeze

connection = ActiveRecord::Base.connection
report = nil
ActiveRecord::Base.transaction do
  connection.execute("SET TRANSACTION READ ONLY")

  # Select an anonymous-eligible source sample, not a captured response. Unlisted
  # (visible=false) topics are deliberately not filtered out: Guardian#can_see?
  # permits some such topics. Exclude private/deleted/shared-draft and restricted categories.
  public_category_ids = Category.where(read_restricted: false).or(Category.where(read_restricted: nil)).select(:id)
  definition_ids = Category.where.not(topic_id: nil).select(:topic_id)
  eligible_topics = Topic.unscoped
    .where(deleted_at: nil, archetype: Archetype.default)
    .where(category_id: public_category_ids)
    .where.not(id: definition_ids)
    .where.not(id: Topic.joins(:shared_draft).select(:id))
  requested_ids = if ENV.key?("TOPIC_ORACLE_IDS")
    values = ENV.fetch("TOPIC_ORACLE_IDS").split(",", -1)
    abort "TOPIC_ORACLE_IDS must be comma-separated positive integers" if values.empty? || values.any? { |value| !value.match?(/\A[1-9][0-9]*\z/) }
    values.map(&:to_i)
  end
  topics = if requested_ids
    found = eligible_topics.where(id: requested_ids).index_by(&:id)
    missing = requested_ids.uniq - found.keys
    abort "topic IDs are not in anonymous source-eligible selection: #{missing.join(',')}" unless missing.empty?
    requested_ids.map { |id| found.fetch(id) }
  else
    eligible_topics.order(bumped_at: :desc, id: :desc)
      .limit(Integer(ENV.fetch("TOPIC_ORACLE_COUNT", "3")))
      .to_a
  end
  abort "no eligible public topics found" if topics.empty?

  post_number_text = ENV.fetch("TOPIC_ORACLE_POST_NUMBER", "1")
  abort "TOPIC_ORACLE_POST_NUMBER must be a positive integer" unless post_number_text.match?(/\A[1-9][0-9]*\z/) && post_number_text.to_i <= 2_147_483_647
  requested_post_number = post_number_text.to_i

  guardian = Guardian.new(nil)
  denied_topic_ids = []
  checked_topic_count = 0
  Topic.unscoped.includes(:category).find_each do |candidate_topic|
    checked_topic_count += 1
    denied_topic_ids << candidate_topic.id unless guardian.can_see?(candidate_topic)
  end

  rows = topics.map do |topic|
    # This is the actual anonymous authorization source of truth; don't equate it
    # with Topic.visible (unlisted topics can be viewable by direct ID).
    view = TopicView.new(topic, nil, post_number: requested_post_number, include_suggested: false, include_related: false)
    abort "Guardian rejected selected topic #{topic.id}" unless guardian.can_see?(topic)
    topic_serializer = TopicViewSerializer.new(view, root: false, scope: guardian)
    conditional_topic_fields = {
      "visibility_reason_id" => topic_serializer.include_visibility_reason_id?,
      "featured_link" => topic_serializer.include_featured_link?,
      "unicode_title" => topic_serializer.include_unicode_title?,
      "current_post_number" => topic_serializer.include_current_post_number?,
    }
    topic_values = TOPIC_SERIALIZER_FIELDS.reject do |field|
      conditional_topic_fields.key?(field) && !conditional_topic_fields[field]
    end.to_h { |field| [field, topic_serializer.public_send(field)] }
    conditional_topic_fields.each do |field, include_field|
      topic_values[field] = topic_serializer.public_send(field) if include_field && !TOPIC_SERIALIZER_FIELDS.include?(field)
    end
    topic_values["current_post_number"] = topic_serializer.current_post_number if conditional_topic_fields["current_post_number"]
    # fancy_title is a direct source getter, not a TopicViewSerializer attribute in this revision.
    topic_values["fancy_title"] = topic.fancy_title
    # Ticket015 bounded anonymous plugin extension, evaluated by the actual
    # serializer getter after its real TopicView preload hook. No fixture data.
    if SiteSetting.discourse_reactions_enabled
      topic_values["valid_reactions"] = topic_serializer.valid_reactions
    end

    details_serializer = TopicViewDetailsSerializer.new(view, root: false, scope: guardian)
    basic_user = lambda do |user|
      user && BasicUserSerializer.new(user, root: false, scope: guardian).as_json
    end
    details_values = {
      "can_edit" => details_serializer.can_edit,
      "notification_level" => details_serializer.notification_level,
      "created_by" => basic_user.call(details_serializer.created_by),
      "last_poster" => basic_user.call(details_serializer.last_poster),
    }

    # TopicView applies source post-type/visibility/deletion policy, sort order,
    # and its first-page limit. Hidden posts remain in the stream with the source
    # BasicPostSerializer's cooked_hidden placeholder; raw content is never read.
    posts = view.posts.to_a
      post_values = posts.map do |post|
        post.topic = topic
        serializer = PostSerializer.new(post, scope: guardian, root: false)
        serializer.topic_view = view
        post_getters = POST_GETTERS.dup
        post_getters.delete("name") unless serializer.include_name?
        post_getters.delete("action_code") unless serializer.include_action_code?
        values = post_getters.to_h do |field, getter|
          [field, serializer.public_send(getter)]
        end
        values["cooked_hidden"] = true if serializer.include_cooked_hidden?
        if SiteSetting.discourse_reactions_enabled
          %w[reactions reaction_users_count current_user_reaction current_user_used_main_reaction].each do |field|
            values[field] = serializer.public_send(field)
          end
        end
        values
      end

      {
        "request" => { "topic_id" => topic.id, "post_number" => requested_post_number, "page" => 1 },
        "topic" => topic_values,
        "details" => details_values,
        "post_stream" => {
          "stream" => view.filtered_post_ids,
          "posts" => post_values,
        },
      }
  end

  # Registered field names (including source plugin extensions), not evaluation
  # of omitted serializers. No missing field is counted as implemented.
  registered_fields = lambda do |klass|
    (klass._attributes.values.map(&:to_s) + klass._associations.keys.map(&:to_s)).uniq.sort
  end
  omissions = {
    "TopicViewSerializer" => registered_fields.call(TopicViewSerializer) - (TOPIC_SERIALIZER_FIELDS + %w[fancy_title visibility_reason_id featured_link unicode_title post_stream details] + (SiteSetting.discourse_reactions_enabled ? %w[valid_reactions] : [])),
    "TopicViewDetailsSerializer" => registered_fields.call(TopicViewDetailsSerializer) - %w[can_edit notification_level created_by last_poster],
    "PostSerializer" => registered_fields.call(PostSerializer) - (POST_GETTERS.keys + %w[cooked_hidden] + (SiteSetting.discourse_reactions_enabled ? %w[reactions reaction_users_count current_user_reaction current_user_used_main_reaction] : [])),
  }
  report = {
    "contract" => "minimal-topic-v1",
    "omitted_registered_fields" => omissions,
    "source_revision" => `git -C ../discourse rev-parse HEAD`.strip,
    "selection" => "bumped_at desc,id desc; Guardian-eligible regular topics in public categories; non-deleted, non-private, non-shared-draft, excluding category definitions; post_number=#{requested_post_number}, TopicView near-post selection, maximum 20 serialized posts",
    "topics_checked_by_guardian" => checked_topic_count,
    "guardian_inaccessible_topic_ids" => denied_topic_ids.sort,
    "reaction_live_counts" => {
      "reactions" => DiscourseReactions::Reaction.count,
      "reaction_users" => DiscourseReactions::ReactionUser.count,
      "likes" => PostAction.where(post_action_type_id: PostActionType::LIKE_POST_ACTION_ID, deleted_at: nil).count,
    },
    "topics" => rows,
    "read_only" => true,
  }
end
puts JSON.pretty_generate(JSON.parse(ActiveSupport::JSON.encode(report)))

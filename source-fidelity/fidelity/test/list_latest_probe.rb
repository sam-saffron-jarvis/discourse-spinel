# TEST observations of the actual list.topics hydration, not model JSON.
module ListLatestObservation
  def self.user(user)
    return nil if user.nil?
    {id: user.id, username: user.username, name: user.name, uploaded_avatar_id: user.uploaded_avatar_id,
     primary_group_id: user.primary_group_id, flair_group_id: user.flair_group_id,
     admin: user.admin, moderator: user.moderator, trust_level: user.trust_level}
  end

  def self.group(group)
    return nil if group.nil?
    {id: group.id, name: group.name, flair_icon: group.flair_icon, flair_upload_id: group.flair_upload_id,
     flair_bg_color: group.flair_bg_color, flair_color: group.flair_color}
  end

  def self.poster(poster)
    actor = poster.user
    raise "primary group cache identity" if actor.primary_group_id && !actor.primary_group.equal?(poster.primary_group)
    raise "flair group cache identity" if actor.flair_group_id && !actor.flair_group.equal?(poster.flair_group)
    {user: user(poster.user), description: poster.description, extras: poster.extras,
     primary_group: group(poster.primary_group), flair_group: group(poster.flair_group)}
  end

  def self.emit(name, options, fixture, preload_unit = false)
    callbacks = TopicQuery.results_filter_callbacks
    saved = callbacks.dup
    saved_fields = TopicList.preloaded_custom_fields
    preload_callback = nil
    begin
      if preload_unit
        TopicList.preloaded_custom_fields = Set.new(["fidelity_missing_cf"])
        preload_callback = lambda do |rows, object|
          raise "preload callback before hydration" unless rows.all? { |row| !row.posters.empty? && row.topic_list.equal?(object) }
          object.publish_read_state = true unless ENV.fetch("FIDELITY_STAGE3B_WRONG_PRELOAD", "0") == "1"
        end
        TopicList.on_preload(&preload_callback)
      end
      if fixture
        callbacks << lambda do |filter, relation, actor, query_options|
          raise "list fixture callback identity/filter" unless actor.nil? && filter == :latest
          if ENV.fetch("FIDELITY_STAGE3B_WRONG_PINNING", "0") == "1"
            relation = relation.where("topics.id <> ?", 101)
          end
          ListLatestProbe.fixture(relation)
        end
      end
      query = ListLatestProbe.build(options)
      list = ListLatestProbe.list(query)
      topics = []
      hydration = FidelityDriver.capture { topics = list.topics }
      observed = []
      categories = []
      repeated = FidelityDriver.capture do
        raise "list topics not memoized" unless list.topics.equal?(topics)
        observed = topics.map do |row|
          raise "list associations not preloaded" unless ListLatestProbe.loaded(row)
          category = row.category
          parent = category.nil? ? nil : category.parent_category
          first_post = row.first_post
          image = row.image_upload
          thumbnails = row.topic_thumbnails.to_a.map do |thumbnail|
            optimized = thumbnail.optimized_image
            {id: thumbnail.id, upload_id: thumbnail.upload_id, max_width: thumbnail.max_width,
             max_height: thumbnail.max_height, optimized_image_id: optimized.nil? ? nil : optimized.id}
          end
          raise "unsafe null-slug fallback is outside readonly list profile" if row.read_attribute(:slug).nil?
          {id: row.id, title: row.title, stored_slug: row.read_attribute(:slug), archetype: row.archetype,
           visible: row.visible, pinned_at: FidelityDriver.timestamp(row.pinned_at), pinned_globally: row.pinned_globally,
           category_id: row.category_id, category_name: category.nil? ? nil : category.name,
           parent_category_id: parent.nil? ? nil : parent.id,
           featured_user_ids: row.featured_user_ids, recent_user_ids: row.featured_users.recent_user_ids,
           posters: row.posters.map { |item| poster(item) }, participants: row.participants.map { |item| poster(item) },
           participant_groups: row.participant_groups, allowed_user_ids: row.allowed_user_ids, allowed_group_ids: row.allowed_group_ids,
           user_data_nil: row.user_data.nil?, category_user_data_nil: row.category_user_data.nil?, dismissed: row.dismissed,
           list_identity: row.topic_list.equal?(list), first_post_id: first_post.nil? ? nil : first_post.id,
           first_post_user_id: first_post.nil? ? nil : first_post.user_id,
           first_post_cooked: first_post.nil? ? nil : first_post.cooked, image_upload_id: image.nil? ? nil : image.id,
           image_upload_url: image.nil? ? nil : image.url, thumbnails: thumbnails,
           preloaded_custom_fields: row.preloaded_custom_fields}
        end
        categories = list.categories.map { |category| [category.id, category.name, category.parent_category_id] }
      end
      raise "repeated list hydration queried" unless repeated.empty?
      puts "FIDELITY " + FidelityDriver.encode({kind: "stage3b_list", name: name, options: options,
        query_options: query.options, filter: list.filter.to_s, per_page: list.per_page, for_period: list.for_period,
        more_topics_url: list.more_topics_url, prev_topics_url: list.prev_topics_url, publish_read_state: list.publish_read_state,
        filter_option_info: list.filter_option_info, filter_new_topic_ids: list.filter_new_topic_ids,
        preload_key: list.preload_key, shared_drafts_nil: list.shared_drafts.nil?, tags_nil: list.tags.nil?,
        category_id: list.category.nil? ? nil : list.category.id, categories: categories, rows: observed})
      puts "FIDELITY_STAGE3B_HYDRATION " + FidelityDriver.encode({name: name, hydration_queries: hydration.length, repeated_queries: repeated.length})
    ensure
      callbacks.replace(saved)
      TopicList.cancel_preload(&preload_callback) if preload_unit
      TopicList.preloaded_custom_fields = saved_fields
    end
  end
end
puts "FIDELITY_STAGE3B_QUERY_ENTER"
ListLatestObservation.emit("live_list", {per_page: 3}, false)
ListLatestObservation.emit("live_page1", {per_page: 3, page: 1}, false)
ListLatestObservation.emit("live_preload_unit", {per_page: 2}, false, true)
ListLatestObservation.emit("fixture_list", {per_page: 5}, true)
ListLatestObservation.emit("fixture_page0", {per_page: 2}, true)
ListLatestObservation.emit("fixture_page1", {per_page: 2, page: 1}, true)
puts "FIDELITY_STAGE3B_MATERIALIZED"

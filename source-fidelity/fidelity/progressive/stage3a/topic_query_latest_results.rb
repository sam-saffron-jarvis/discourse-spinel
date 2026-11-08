# frozen_string_literal: true
# Supported anonymous latest_results ONLY, not TopicList hydration or page.
class TopicQueryLatestResults < TopicQueryDefaultResults
  def self.validate_options!(options, internal = false)
    super(options, internal)
    raise ArgumentError, "unsupported shared-drafts profile" unless SiteSetting.shared_drafts_category == ""
  end

  def self.results_filter_callbacks
    TopicQuery.results_filter_callbacks
  end

  def default_results(options = {})
    results(options)
  end

  def latest_results(options = {})
    result = default_results(options)
    result = remove_muted(result, @user, options)
    result = apply_shared_drafts(result, get_category_id(options[:category]), options)

    # plugins can remove topics here:
    self.class.results_filter_callbacks.each do |filter_callback|
      result = filter_callback.call(:latest, result, @user, options)
    end

    result
  end

  def remove_muted(list, user, options)
    if options && (options[:include_muted].nil? || options[:include_muted]) &&
         options[:state] != "muted"
      list = remove_muted_topics(list, user)
    end

    list = remove_muted_categories(list, user, exclude: options[:category])
    self.class.remove_muted_tags(list, user, options)
  end

  def remove_muted_topics(list, user)
    raise ArgumentError, "unsupported authenticated muted-topic profile" unless user.nil?
    

    list
  end

  def remove_muted_categories(list, user, opts = nil)
    raise ArgumentError, "unsupported authenticated category-mute profile" unless user.nil?
    category_id = get_category_id(opts[:exclude]) if opts

    if SiteSetting.mute_all_categories_by_default
      category_ids = [
        SiteSetting.default_categories_watching.split("|"),
        SiteSetting.default_categories_tracking.split("|"),
        SiteSetting.default_categories_watching_first_post.split("|"),
        SiteSetting.default_categories_normal.split("|"),
      ].flatten.map(&:to_i)
      category_ids << category_id if category_id.present? && !category_ids.include?(category_id)

      list = list.where("categories.id IN (?)", category_ids) if category_ids.present?
    else
      category_ids = SiteSetting.default_categories_muted.split("|").map(&:to_i)
      category_ids -= [category_id] if category_id.present? && category_ids.include?(category_id)

      list = list.where.not(categories: { id: category_ids }) if category_ids.present?
    end

    list
  end

  def self.remove_muted_tags(list, user, opts = {})
    raise ArgumentError, "unsupported authenticated muted-tag profile" unless user.nil?
    if !SiteSetting.tagging_enabled || SiteSetting.remove_muted_tags_from_latest == "never"
      return list
    end

    muted_tag_ids = []

    muted_tag_names = SiteSetting.default_tags_muted.split("|")

      muted_tag_ids = Tag.where(name: muted_tag_names).pluck(:id) if muted_tag_names.present?

    return list if muted_tag_ids.blank?

    # if viewing the topic list for a muted tag, show all the topics
    

    query_params = { tag_ids: muted_tag_ids }

    

    if SiteSetting.remove_muted_tags_from_latest == "always"
      list =
        list.where(
          "
        NOT EXISTS(
          SELECT 1
            FROM topic_tags tt
           WHERE tt.tag_id IN (:tag_ids)
             AND tt.topic_id = topics.id
             #{user && !opts[:skip_categories] ? "AND COALESCE(category_users.notification_level, :regular) < :watching_or_infinite" : ""})",
          query_params,
        )
    else
      list =
        list.where(
          "
        EXISTS (
          SELECT 1
            FROM topic_tags tt
           WHERE (tt.tag_id NOT IN (:tag_ids)
             AND tt.topic_id = topics.id)
             #{user && !opts[:skip_categories] ? "OR COALESCE(category_users.notification_level, :regular) >= :watching_or_infinite" : ""}
        ) OR NOT EXISTS (SELECT 1 FROM topic_tags tt WHERE tt.topic_id = topics.id)",
          query_params,
        )
    end
  end

  def apply_shared_drafts(result, category_id, options)
    return result if SiteSetting.shared_drafts_category == ""
    raise ArgumentError, "unsupported shared-drafts profile"
  end
end

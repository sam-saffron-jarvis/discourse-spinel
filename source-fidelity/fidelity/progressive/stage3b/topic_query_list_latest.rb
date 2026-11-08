# frozen_string_literal: true
# Supported anonymous :latest list dispatcher, including original pinning.
class TopicQueryListLatest < TopicQueryLatestResults
  def self.validate_options!(options, internal = false)
    checked = options.dup
    if checked.key?(:filter)
      raise ArgumentError, "unsupported list filter" unless checked[:filter] == :latest || checked[:filter] == "latest"
      checked.delete(:filter)
    end
    super(checked, internal)
    raise ArgumentError, "unlimited list profile unsupported" if options[:limit] == false
    raise ArgumentError, "unsupported list locale" unless I18n.locale.to_s == "en"
  end

  def list_latest
    create_list(:latest, {}, latest_results)
  end

  def create_list(filter, options = {}, topics = nil)
    raise ArgumentError, "unsupported list profile" unless filter == :latest && @user.nil?
    options[:filter] ||= filter
    topics ||= default_results(options)
    topics = yield(topics) if block_given?
    topics =
      DiscoursePluginRegistry.apply_modifier(:topic_query_create_list_topics, topics, options, self)

    options = options.merge(@options)

    apply_pinning = filter != :private_messages
    apply_pinning &&= %w[activity default].include?(options[:order] || "activity")
    apply_pinning &&= !options[:unordered] || options[:prioritize_pinned]

    topics = prioritize_pinned_topics(topics, options) if apply_pinning

    topics = topics.to_a

    if options[:preload_posters]
      user_ids = []
      topics.each do |ft|
        user_ids << ft.user_id << ft.last_post_user_id << ft.featured_user_ids <<
          ft.allowed_user_ids
      end

      user_lookup = UserLookup.new(user_ids)

      # memoize for loop so we don't keep looking these up
      translations = TopicPostersSummary.translations

      topics.each do |t|
        t.posters = t.posters_summary(user_lookup: user_lookup, translations: translations)
      end
    end

    topics.each do |t|
      t.allowed_user_ids = []
        t.allowed_group_ids = []
    end

    list = TopicList.new(filter, @user, topics, options.merge(@options))
    list.per_page = options[:per_page]&.to_i || per_page_setting


    list
  end

  def prioritize_pinned_topics(topics, options)
    pinned_clause =
      if options[:category_id]
        +"topics.category_id = #{options[:category_id].to_i} AND"
      else
        +"pinned_globally AND "
      end

    pinned_clause << " pinned_at IS NOT NULL "

    if @user
      pinned_clause << " AND (topics.pinned_at > tu.cleared_pinned_at OR tu.cleared_pinned_at IS NULL)"
    end

    unpinned_topics = topics.where("NOT ( #{pinned_clause} )")
    pinned_topics = topics.dup.offset(nil).where(pinned_clause).reorder(pinned_at: :desc)

    per_page = options[:per_page]&.to_i || per_page_setting
    limit = per_page unless options[:limit] == false
    page = options[:page].to_i

    if page == 0
      (pinned_topics + unpinned_topics)[0...limit] if limit
    else
      offset = (page * per_page) - pinned_topics.length
      offset = 0 if offset <= 0
      unpinned_topics.offset(offset).to_a
    end
  end
end

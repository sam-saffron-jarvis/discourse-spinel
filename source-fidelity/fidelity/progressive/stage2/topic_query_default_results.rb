# frozen_string_literal: true
# Complete default_results BEHAVIOR for the explicitly supported anonymous
# profile below, not all TopicQuery request options, latest/list or page.
class TopicQueryDefaultResults
  DEFAULT_PER_PAGE_COUNT = 30

  SORTABLE_MAPPING = {
    "likes" => "like_count",
    "op_likes" => "op_likes",
    "views" => "views",
    "posts" => "posts_count",
    "activity" => "bumped_at",
    "posters" => "participant_count",
    "category" => "category_id",
    "created" => "created_at",
  }
  attr_accessor :options
  attr_reader :user, :guardian

  def initialize(options = {})
    self.class.validate_options!(options)
    @options = options.dup
    @user = nil
    @guardian = Guardian.new(nil)
  end

  def self.validate_options!(options, internal = false)
    allowed = [:page, :per_page, :visible, :limit, :category, :no_subcategories, :no_definitions, :except_topic_ids, :topic_ids, :order, :ascending, :no_tags, :min_posts, :max_posts]
    allowed << :category_id if internal
    options.each_key { |key| raise ArgumentError, "unsupported default_results profile option: #{key}" unless allowed.include?(key) }
    raise ArgumentError, "unsupported nested replies profile" if SiteSetting.nested_replies_enabled
    raise ArgumentError, "unsupported localization profile" if SiteSetting.content_localization_enabled
    [:page, :per_page, :min_posts, :max_posts].each do |key|
      value = options[key]
      raise ArgumentError, "unsupported integer option: #{key}" if value && (!value.is_a?(Integer) || value < 0 || value > 1000)
    end
    raise ArgumentError, "per_page must be positive" if options[:per_page] == 0
    raise ArgumentError, "unlimited paging needs per_page" if options[:limit] == false && options[:page] && !options[:per_page]
    raise ArgumentError, "unsupported limit" unless options[:limit].nil? || options[:limit] == false
    raise ArgumentError, "anonymous visibility must be default/true" unless options[:visible].nil? || options[:visible] == true
    raise ArgumentError, "unsupported category" unless options[:category].nil? || options[:category].is_a?(String)
    [:no_subcategories, :no_definitions, :no_tags].each do |key|
      value = options[key]
      raise ArgumentError, "unsupported boolean option: #{key}" unless value.nil? || value == true || value == false || value == "true" || value == "false"
    end
    [:except_topic_ids, :topic_ids].each do |key|
      value = options[key]
      unless value.nil?
        raise ArgumentError, "unsupported id list" unless value.is_a?(Array)
        value.each { |id| raise ArgumentError, "unsupported id" unless id.is_a?(Integer) }
      end
    end
    order = options[:order]
    raise ArgumentError, "unsupported order" unless order.nil? || order == "default" || (SORTABLE_MAPPING.key?(order) && order != "op_likes")
    ascending = options[:ascending]
    raise ArgumentError, "unsupported ascending" unless ascending.nil? || ascending == "true" || ascending == "false"
  end

  def results(options = {})
    self.class.validate_options!(options)
    self.class.validate_options!(@options, true)
    raise ArgumentError, "unsupported identity profile" unless @user.nil? && @guardian.instance_of?(Guardian)
    options.reverse_merge!(@options)
    options.reverse_merge!(per_page: per_page_setting) unless options[:limit] == false

    # Whether to include unlisted (visible = false) topics
    viewing_own_topics = @user && @user.id == options[:filtered_to_user]

    if options[:visible].nil?
      options[:visible] = true if @user.nil? || @user.regular?
      options[:visible] = false if @guardian.can_see_unlisted_topics? || viewing_own_topics
    end

    # Start with a list of all topics
    result = Topic.includes(:category)
    result = result.includes(:nested_topic) if SiteSetting.nested_replies_enabled

    

    category_id = get_category_id(options[:category])
    @options[:category_id] = category_id
    if category_id
      if ActiveModel::Type::Boolean.new.cast(options[:no_subcategories])
        result = result.where("topics.category_id = ?", category_id)
      else
        result = result.where("topics.category_id IN (?)", subcategory_ids(category_id))
        if !SiteSetting.show_category_definitions_in_topic_lists
          result =
            result.where(
              "categories.topic_id IS DISTINCT FROM topics.id OR topics.category_id = ?",
              category_id,
            )
        end
      end
      result = result.references(:categories)

      if !@options[:order]
        filter = options[:filter] || options[:f]
        # category default sort order
        sort_order, sort_ascending =
          Category.where(id: category_id).pick(:sort_order, :sort_ascending)
        if sort_order && (filter.blank? || %w[default latest unseen].include?(filter.to_s))
          options[:order] = sort_order
          options[:ascending] = !!sort_ascending ? "true" : "false"
        else
          options[:order] = "default"
          options[:ascending] = "false"
        end
      end
    end

    if SiteSetting.tagging_enabled
      # Use `preload` here instead since `includes` can end up calling `eager_load` which can unnecessarily lead to
      # joins on the `topic_tags` and `tags` table leading to a much slower query.
      result =
        if SiteSetting.content_localization_enabled
          result.preload(tags: :localizations)
        else
          result.preload(:tags)
        end
      result = filter_by_tags(result)
    end

    result = apply_ordering(result, options) if !options[:skip_ordering]

    all_listable_topics =
      @guardian.filter_allowed_categories(
        Topic.unscoped.listable_topics,
        category_id_column: "categories.id",
      )

    result = result.merge(all_listable_topics)

    # Don't include the category topics if excluded
    if options[:no_definitions]
      result = result.where("COALESCE(categories.topic_id, 0) <> topics.id")
    end

    result = result.limit(options[:per_page]&.to_i) unless options[:limit] == false
    result = result.visible if options[:visible]
    result =
      result.where.not(topics: { id: options[:except_topic_ids] }).references(:topics) if options[
      :except_topic_ids
    ]

    if options[:page]
      offset = options[:page].to_i * options[:per_page]&.to_i
      result = result.offset(offset) if offset > 0
    end

    if options[:topic_ids]
      result = result.where("topics.id in (?)", options[:topic_ids]).references(:topics)
    end

    

    

    

    

    

    

    result = result.where("topics.posts_count <= ?", options[:max_posts]) if options[
      :max_posts
    ].present?
    result = result.where("topics.posts_count >= ?", options[:min_posts]) if options[
      :min_posts
    ].present?

    result = TopicQuery.apply_custom_filters(result, self)

    result
  end

  def per_page_setting
    DEFAULT_PER_PAGE_COUNT
  end

  def apply_ordering(result, options = {})
    order_option = options[:order]
    sort_dir = (options[:ascending] == "true") ? "ASC" : "DESC"

    new_result =
      DiscoursePluginRegistry.apply_modifier(
        :topic_query_apply_ordering_result,
        result,
        order_option,
        sort_dir,
        options,
        self,
      )
    return new_result if !new_result.nil? && new_result != result
    sort_column = SORTABLE_MAPPING[order_option] || "default"

    # If we are sorting in the default order desc, we should consider including pinned
    # topics. Otherwise, just use bumped_at.
    if sort_column == "default"
      if sort_dir == "DESC"
        # If something requires a custom order, for example "unread" which sorts the least read
        # to the top, do nothing
        return result if options[:unordered]
      end
      sort_column = "bumped_at"
    end

    # If we are sorting by category, actually use the name
    if sort_column == "category_id"
      # TODO forces a table scan, slow
      return result.references(:categories).order(<<~SQL)
        CASE WHEN categories.id = #{SiteSetting.uncategorized_category_id.to_i} THEN '' ELSE categories.name END #{sort_dir}
      SQL
    end

    if sort_column == "op_likes"
      return(
        result.includes(:first_post).order(
          "(SELECT like_count FROM posts p3 WHERE p3.topic_id = topics.id AND p3.post_number = 1) #{sort_dir}",
        )
      )
    end

    if sort_column.start_with?("custom_fields")
      field = sort_column.split(".")[1]
      return(
        result.order(
          "(SELECT CASE WHEN EXISTS (SELECT true FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') THEN (SELECT value::integer FROM topic_custom_fields tcf WHERE tcf.topic_id::integer = topics.id::integer AND tcf.name = '#{field}') ELSE 0 END) #{sort_dir}",
        )
      )
    end

    result.order("topics.#{sort_column} #{sort_dir}")
  end

  def get_category_id(category_id_or_slug)
    return nil if category_id_or_slug.blank?
    category_id = category_id_or_slug.to_i

    if category_id == 0
      category_id = Category.where(slug: category_id_or_slug, parent_category_id: nil).pick(:id)
    end

    category_id
  end

  def filter_by_tags(result)
    if ActiveModel::Type::Boolean.new.cast(@options[:no_tags])
      # the following will do: ("topics"."id" NOT IN (SELECT DISTINCT "topic_tags"."topic_id" FROM "topic_tags"))
      result = result.where.not(id: TopicTag.distinct.select(:topic_id))
    end
    result
  end

  def subcategory_ids(category_id)
      sql = <<~SQL
            WITH RECURSIVE subcategories AS (
                SELECT ? id, 1 depth
                UNION
                SELECT categories.id, (subcategories.depth + 1) depth
                FROM categories
                JOIN subcategories ON subcategories.id = categories.parent_category_id
                WHERE subcategories.depth < ?
            )
            SELECT id FROM subcategories
          SQL
      ActiveRecord::Base.connection.select_rows(
        ActiveRecord::Base.sanitize_sql_array([sql, category_id, SiteSetting.max_category_nesting]),
      ).map { |row| row[0].to_i }
      end
end

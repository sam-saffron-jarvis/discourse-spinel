options.reverse_merge!(@options)

options.reverse_merge!(per_page: per_page_setting) unless options[:limit] == false

viewing_own_topics = @user && @user.id == options[:filtered_to_user]

if options[:visible].nil?
      options[:visible] = true if @user.nil? || @user.regular?
      options[:visible] = false if @guardian.can_see_unlisted_topics? || viewing_own_topics
    end

result = Topic.includes(:category)

all_listable_topics =
      @guardian.filter_allowed_categories(
        Topic.unscoped.listable_topics,
        category_id_column: "categories.id",
      )

result = result.merge(all_listable_topics)

result = result.limit(options[:per_page]&.to_i) unless options[:limit] == false

result = result.visible if options[:visible]

if options[:page]
      offset = options[:page].to_i * options[:per_page]&.to_i
      result = result.offset(offset) if offset > 0
    end

result

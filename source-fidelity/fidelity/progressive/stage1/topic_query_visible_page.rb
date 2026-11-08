# frozen_string_literal: true
# PARTIAL default_results: anonymous default visibility/security/limit/offset.
# Ordering/category/tag/search/nested/list hydration are NOT admitted here.
class TopicQueryVisiblePage
  DEFAULT_PER_PAGE_COUNT = 30

  def initialize
    @guardian = Guardian.new
    @user = nil
    @options = {}
  end

  def self.validate_options!(options)
    allowed = [:page, :per_page, :visible, :limit]
    options.each_key do |key|
      raise ArgumentError, "unsupported partial default_results option: #{key}" unless allowed.include?(key)
    end
    page = options[:page]
    per_page = options[:per_page]
    raise ArgumentError, "unsupported page" if page && (!page.is_a?(Integer) || page < 0 || page > 100)
    raise ArgumentError, "unsupported per_page" if per_page && (!per_page.is_a?(Integer) || per_page < 1 || per_page > 100)
    raise ArgumentError, "anonymous visibility must be default/true" unless options[:visible].nil? || options[:visible] == true
    raise ArgumentError, "unsupported limit" unless options[:limit].nil? || options[:limit] == false
    raise ArgumentError, "unlimited paging requires per_page" if options[:limit] == false && page && !per_page
  end

  def results(options = {})
    self.class.validate_options!(options)
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

  end

  def per_page_setting
    DEFAULT_PER_PAGE_COUNT
  end
end

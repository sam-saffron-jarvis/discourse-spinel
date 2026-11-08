# frozen_string_literal: true
# Isolated original full template engine + OutputBuffer, not a Rails request.
require "active_support/core_ext/module/delegation"
require "action_view/buffers"
require "delegate"
require_relative "original_list_body"
require_relative "original_renderer_sequence"
require_relative "original_topic_urls"
require_relative "original_category_url"
require_relative "original_template_helpers"
class RefusingOriginalCategoryCache
  def initialize(view); @view = view; end
  def defer_get_set(key)
    @view.category_url_capability_key(key)
  end
end
class OriginalTemplateCategory < SimpleDelegator
  include OriginalCategoryUrl
  def initialize(category, view)
    super(category)
    OriginalCategoryUrl.class_variable_set(:@@url_cache, RefusingOriginalCategoryCache.new(view))
  end
end
class OriginalTemplateTopic < SimpleDelegator
  include OriginalTopicUrls
  def initialize(topic, view)
    super(topic)
    @view = view
  end
  def self.url(id, slug, post_number = nil); Topic.url(id, slug, post_number); end
  def category
    value = __getobj__.category
    value && OriginalTemplateCategory.new(value, @view)
  end
end
class OriginalTemplateList < SimpleDelegator
  def initialize(list, view)
    super(list)
    @view = view
  end
  def topics; __getobj__.topics.map { |topic| OriginalTemplateTopic.new(topic, @view) }; end
end
class OriginalListTemplateContext < ListTemplatePrefixContext
  include OriginalListBody
  include OriginalTemplateApplicationHelpers
  def initialize(controller)
    super
    @list = OriginalTemplateList.new(controller.html_stage_list, self)
  end
  def prefix_snapshot; @output_buffer.to_s.to_str; end
  def category_url_capability_key(key)
    raise "original cache key changed" unless key == @controller.html_stage_list.topics.first.category.id.to_s
    category_url_capability(@controller.html_stage_list.topics.first.category)
  end
end
class ListTemplatePrefixRenderer
  include OriginalRendererSequence
end
class HtmlStageObservedController
  def template_context; OriginalListTemplateContext.new(self); end
end

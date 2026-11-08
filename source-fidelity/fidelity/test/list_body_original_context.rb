# frozen_string_literal: true
require_relative "original_list_body_models"
require_relative "original_list_date"
module OriginalListDate
  module I18n
    def self.t(key, **options)
      name = key.to_s
      if %w[date.abbr_day_names date.day_names date.abbr_month_names date.month_names].include?(name)
        JSON.parse(File.read(File.join(Rails.root.to_s, "config/list_date_names.json")))[(options[:locale] || ::I18n.locale).to_s][name]
      else
        ::I18n.translate_runtime(name, options.reject { |k, _| [:object, :format, :raise].include?(k) }, "", false, options[:raise] == true)
      end
    end
    def self.t!(key, **options); t(key, **options); end
    def self.l(value, format: :default)
      Localizer.new.localize(::I18n.locale, value, format, {})
    end
  end
end
module OriginalListBody
  I18n = OriginalListDate::I18n
end
module OriginalBodyPoster
  I18n = OriginalListDate::I18n
end
class OriginalTemplateCategory
  def url
    value = super
    CategoryCacheBootstrap.lease.note_category_url(__getobj__.id.to_s, value)
    value
  end
end
class OriginalTemplateTopic
  include OriginalBodyTopic
  def tags; __getobj__.tags.to_a; end
  def posters
    __getobj__.posters.map { |poster| OriginalBodyPosterRecord.new(poster) }
  end
end
class OriginalBodyPosterRecord < SimpleDelegator
  include OriginalBodyPoster
  def user; OriginalBodyUserRecord.new(__getobj__.user); end
end
class OriginalBodyUserRecord < SimpleDelegator
  include OriginalBodyUser
end
class OriginalListBodyContext < OriginalListTemplateContext
  include ListBodyViewProtocol
  def initialize(controller)
    super
    acquire_body_assigns(controller)
  end
  def h(value); ERB::Util.html_escape(value).html_safe; end
  def capture_list_body
    @output_buffer.capture do
      begin
        yield
      rescue HtmlRenderingBoundary
        @incomplete_capture = @output_buffer.to_s.to_str
        raise
      end
    end
  end
  def observation; body_stage_observation; end
end
class HtmlStageObservedController
  def template_context; OriginalListBodyContext.new(self); end
end

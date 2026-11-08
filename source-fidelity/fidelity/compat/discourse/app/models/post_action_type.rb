# frozen_string_literal: true

class PostActionType < ActiveRecord::Base
  POST_ACTION_TYPE_ALL_FLAGS_KEY = "post_action_type_all_flags"
  POST_ACTION_TYPE_PUBLIC_TYPE_IDS_KEY = "post_action_public_type_ids"
  LIKE_POST_ACTION_ID = 2

  after_save { expire_cache if !skip_expire_cache_callback }
  after_destroy { expire_cache if !skip_expire_cache_callback }

  attr_accessor :skip_expire_cache_callback

  include AnonCacheInvalidator

  def expire_cache
    Discourse.cache.redis.del(
      *I18n.available_locales.map do |locale|
        Discourse.cache.normalize_key("post_action_types_#{locale}")
      end,
      *I18n.available_locales.map do |locale|
        Discourse.cache.normalize_key("post_action_flag_types_#{locale}")
      end,
      Discourse.cache.normalize_key(POST_ACTION_TYPE_ALL_FLAGS_KEY),
      Discourse.cache.normalize_key(POST_ACTION_TYPE_PUBLIC_TYPE_IDS_KEY),
    )
  end

  class << self
    attr_reader :flag_settings

    def initialize_flag_settings
      @flag_settings = FlagSettings.new
    end

    def replace_flag_settings(settings)
      Discourse.deprecate("Flags should not be replaced. Insert custom flags as database records.")
      @flag_settings = settings || FlagSettings.new
    end

    def reload_types
      @flag_settings = FlagSettings.new
      PostActionType.new.expire_cache
      ReviewableScore.reload_types
    end

    def expire_cache(*args)
      PostActionTypeView.new.expire_cache(*args)
    end

    def all_flags(*args)
      PostActionTypeView.new.all_flags(*args)
    end

    def types(*args)
      PostActionTypeView.new.types(*args)
    end

    def overridden_by_plugin_or_skipped_db?(*args)
      PostActionTypeView.new.overridden_by_plugin_or_skipped_db?(*args)
    end

    def auto_action_flag_types(*args)
      PostActionTypeView.new.auto_action_flag_types(*args)
    end

    def public_types(*args)
      PostActionTypeView.new.public_types(*args)
    end

    def public_type_ids(*args)
      PostActionTypeView.new.public_type_ids(*args)
    end

    def flag_types_without_additional_message(*args)
      PostActionTypeView.new.flag_types_without_additional_message(*args)
    end

    def flags(*args)
      PostActionTypeView.new.flags(*args)
    end

    def flag_types(*args)
      PostActionTypeView.new.flag_types(*args)
    end

    def score_types(*args)
      PostActionTypeView.new.score_types(*args)
    end

    def notify_flag_type_ids(*args)
      PostActionTypeView.new.notify_flag_type_ids(*args)
    end

    def notify_flag_types(*args)
      PostActionTypeView.new.notify_flag_types(*args)
    end

    def topic_flag_types(*args)
      PostActionTypeView.new.topic_flag_types(*args)
    end

    def disabled_flag_types(*args)
      PostActionTypeView.new.disabled_flag_types(*args)
    end

    def additional_message_types(*args)
      PostActionTypeView.new.additional_message_types(*args)
    end

    def names(*args)
      PostActionTypeView.new.names(*args)
    end

    def descriptions(*args)
      PostActionTypeView.new.descriptions(*args)
    end

    def applies_to(*args)
      PostActionTypeView.new.applies_to(*args)
    end

    def is_flag?(*args)
      PostActionTypeView.new.is_flag?(*args)
    end
  end

  initialize_flag_settings
end

# == Schema Information
#
# Table name: post_action_types
#
#  id                  :integer          not null, primary key
#  icon                :string(20)
#  is_flag             :boolean          default(FALSE), not null
#  name_key            :string(50)       not null
#  position            :integer          default(0), not null
#  reviewable_priority :integer          default(0), not null
#  score_bonus         :float            default(0.0), not null
#  created_at          :datetime         not null
#  updated_at          :datetime         not null
#

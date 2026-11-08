# frozen_string_literal: true
module ActionView
  # Explicit trusted HTML result for typed helper boundaries. This is not a
  # String subclass or a replacement for the full ActiveSupport::SafeBuffer API.
  # A consumer must retain/check the wrapper; converting to String drops trust.
  class HtmlFragment
    def initialize(text)
      @text = text.dup.freeze
    end

    def html_safe?
      true
    end

    def html_safe
      self
    end

    def to_s
      @text.dup
    end
  end
end

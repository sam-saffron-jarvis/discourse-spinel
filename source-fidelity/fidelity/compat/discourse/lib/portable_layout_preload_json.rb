# frozen_string_literal: true
# GENERATED exact isolated methods; standalone JSON unit context, not full Rails encoder.
require "json"
module PortableLayoutPreloadMethods
def escape_unicode(javascript)
    if javascript
      javascript = javascript.scrub
      javascript.gsub!(/\342\200\250/u, "&#x2028;")
      javascript.gsub!(%r{(</)}u, '\u003C/')
      javascript
    else
      ""
    end
  end

def preloaded_json
    return "{}" if !@application_layout_preloader

    @application_layout_preloader
      .preloaded_data
      .transform_values { |value| escape_unicode(value) }
      .to_json
  end
end

# frozen_string_literal: true
# GENERATED exact original preload script span; not real Site/preload data.
module PortableApplicationPreloadFragment
  def render_preload_fragment
    output = +"      <discourse-assets-json>\n        <script type=\"application/json\" id=\"data-preloaded\">"
    value = preloaded_json
    raise TypeError, "preloaded JSON must be a String" unless value.is_a?(String)
    # Original raw(value) => value.to_s.html_safe; do not HTML-escape JSON.
    output << value
    output << "</script>\n      </discourse-assets-json>\n"
    ActionView::HtmlFragment.new(output)
  end
end

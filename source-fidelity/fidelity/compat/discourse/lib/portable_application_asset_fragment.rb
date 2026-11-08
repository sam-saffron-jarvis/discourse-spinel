# frozen_string_literal: true
# GENERATED concrete pinned application layout asset fragment, NOT a page.
require "erb"
module PortableApplicationAssetFragment
def render_asset_fragment
output = +""
output << "    <link rel=\"preload\" href=\""
value_0 = (script_asset_path "js/browser-update")
raise TypeError, "non-string layout expression" unless value_0.is_a?(String)
output << ERB::Util.html_escape(value_0)
output << "\" as=\"script\" nonce=\""
value_1 = (csp_nonce_placeholder)
raise TypeError, "non-string layout expression" unless value_1.is_a?(String)
output << ERB::Util.html_escape(value_1)
output << "\">\n\n    "
value_2 = (preload_script 'js/browser-detect')
raise TypeError, "lost typed trusted fragment" unless value_2.is_a?(ActionView::HtmlFragment)
output << value_2.to_s
output << "\n\n    "
value_3 = (module_preloads_for "discourse", (staff? ? "admin/compat-modules" : nil))
raise TypeError, "lost typed trusted fragment" unless value_3.is_a?(ActionView::HtmlFragment)
output << value_3.to_s
output << "\n\n"
ActionView::HtmlFragment.new(output)
end
end

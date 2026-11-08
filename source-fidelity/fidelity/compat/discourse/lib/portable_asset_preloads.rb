# frozen_string_literal: true
# GENERATED isolated helper dependency, not an HTML request.
require "erb"
module PortableAssetPreloadMethods
def preload_script(script, type_module: false, attrs: {})
    resolved_script = asset_chunks[script]&.first || script
    path = script_asset_path(resolved_script)
    preload_script_url(path, entrypoint: script, type_module:, attrs:).html_safe
  end

def preload_script_url(url, entrypoint: nil, type_module: false, attrs: nil)
    entrypoint_attribute = entrypoint ? "data-discourse-entrypoint=\"#{entrypoint}\"" : ""
    nonce_attribute = "nonce=\"#{csp_nonce_placeholder}\""

    extra_attrs =
      attrs&.map { |k, v| "#{ERB::Util.html_escape(k)}=\"#{ERB::Util.html_escape(v)}\"" }&.join(" ")
    extra_attrs = " #{extra_attrs}" if extra_attrs && !extra_attrs.empty?

    add_resource_preload_list(url, "script")

    ActionView::HtmlFragment.new(<<~HTML)
      <script #{type_module ? 'type="module"' : "defer"} src="#{url}" #{entrypoint_attribute}#{extra_attrs} #{nonce_attribute}></script>
    HTML
  end

def module_preloads_for(*scripts)
    resolved_preload_scripts =
      scripts.compact.flat_map { |script| asset_chunks[script] }.compact.uniq

    modulepreload_tags = resolved_preload_scripts.map { |script| <<~HTML }
      <link rel="modulepreload" href="#{script_asset_path script}" nonce="#{csp_nonce_placeholder}">
    HTML

    ActionView::HtmlFragment.new(modulepreload_tags.join("\n"))
  end

def add_resource_preload_list(resource_url, type)
    links =
      controller.asset_preload_links ||
        (controller.asset_preload_links = [])
    links << %Q(<#{resource_url}>; rel="preload"; as="#{type}")
  end
end

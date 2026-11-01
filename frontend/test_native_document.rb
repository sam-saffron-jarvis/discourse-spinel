# frozen_string_literal: true

require "minitest/autorun"
require "json"
require "uri"
require_relative "native_document"

class NativeDocumentTest < Minitest::Test
  def test_prefixed_bootstrap_uses_real_assets_and_safe_preload_json
    title = "</ScRiPt><img src=x> & <!-- comment -->"
    preloads = { "topic_list" => JSON.generate("topics" => [{ "title" => title }]) }
    html = NativeDocument.new("/node/jarvis/widgets/discourse-spinel-app").render(
      preloads,
      { "default_locale" => "en", "secret_site_setting" => "must-not-leak" },
      "https://hub.samsaffron.com",
    )

    assert_includes html, 'id="data-preloaded"'
    assert_includes html, 'id="main"'
    refute_match(/<table\b/i, html)
    refute_includes html, "must-not-leak"
    assert_includes html, 'data-base-uri="/node/jarvis/widgets/discourse-spinel-app"'
    assert_match(%r{href="/node/jarvis/widgets/discourse-spinel-app/assets/native/css/common.css"}, html)
    assert_match(%r{href="/node/jarvis/widgets/discourse-spinel-app/assets/native/css/color-definitions.css"}, html)
    assert_match(%r{src="/node/jarvis/widgets/discourse-spinel-app/assets/native/locale/en.js"}, html)
    assert_match(%r{src="/node/jarvis/widgets/discourse-spinel-app/assets/discourse/assets/js/discourse-.*\.digested\.js"}, html)

    preload_body = html[/<script type="application\/json" id="data-preloaded">(.*?)<\/script>/m, 1]
    refute_nil preload_body
    refute_includes preload_body, "<"
    unpacked = JSON.parse(preload_body)
    assert_equal title, JSON.parse(unpacked.fetch("topic_list")).dig("topics", 0, "title")

    encoded = html[/<meta name="discourse\/config\/environment" content="([^"]+)"/, 1]
    config = JSON.parse(URI.decode_www_form_component(encoded))
    assert_equal "/node/jarvis/widgets/discourse-spinel-app", config.fetch("rootURL")
    assert_equal "production", config.fetch("environment")

    worker = NativeDocument.new("/node/jarvis/widgets/discourse-spinel-app").render_service_worker(
      "https://hub.samsaffron.com",
    )
    assert_includes worker, "https://hub.samsaffron.com/node/jarvis/widgets/discourse-spinel-app/push_notifications/subscribe"
    assert_includes worker, "var SHARE_TARGET_PATH = '/node/jarvis/widgets/discourse-spinel-app/share-target';"
    assert_includes worker, 'self.addEventListener(\'push\''
    refute_includes worker, "__MINIMAL_BASE_"
  end

  def test_rejects_traversal_prefix_and_bad_preload_json
    assert_raises(ArgumentError) { NativeDocument.new("/a/../b") }
    assert_raises(JSON::ParserError) do
      NativeDocument.new("").render({ "site" => "not json" }, {}, "http://127.0.0.1:3498")
    end
  end
end

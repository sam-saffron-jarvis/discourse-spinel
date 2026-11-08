# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../../action_view/source_asset_paths"

class SourceAssetPathsTest < Minitest::Test
  def test_source_digest_version_predigested_names_and_missing_files
    Dir.mktmpdir("source-assets-owner-") do |root|
      File.binwrite(File.join(root, "plain.js"), "owner-source")
      File.binwrite(File.join(root, "app-abcdefgh.digested.js"), "owner-digested")
      a = ActionView::SourceAssetResolver.new(ActionView::SourceAssetLoadPath.new([root], "v1"), "/assets")
      b = ActionView::SourceAssetResolver.new(ActionView::SourceAssetLoadPath.new([root], "v2"), "/assets")
      assert_nil a.resolve("missing.js")
      assert_equal "/assets/app-abcdefgh.digested.js", a.resolve("app-abcdefgh.digested.js")
      refute_equal a.resolve("plain.js"), b.resolve("plain.js")
      expected = Digest::SHA1.hexdigest("owner-sourcev1")[0, 8]
      assert_equal "/assets/plain-#{expected}.js", a.resolve("plain.js")
      paths = ActionView::SourceAssetPaths.new(a, "/unit", "https://cdn.unit.invalid")
      assert_equal "https://cdn.unit.invalid/unit/assets/plain-#{expected}.js?x=1&y=2", paths.asset_path("plain.js?x=1&y=2")
      error = assert_raises(Propshaft::MissingAssetError) { paths.asset_path("missing.js") }
      assert_equal "The asset 'missing.js' was not found in the load path.", error.message
      assert_raises(ArgumentError) { ActionView::SourceAssetPaths.new(a, nil, "cdn%d.unit.invalid") }
    end
  end
end

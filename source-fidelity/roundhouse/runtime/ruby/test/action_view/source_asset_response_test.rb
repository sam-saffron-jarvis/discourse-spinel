# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require_relative "../../action_view/source_asset_paths"
require_relative "../../action_view/source_asset_response"

class SourceAssetResponseTest < Minitest::Test
  def test_get_head_stale_digest_and_explicit_profile_refusals
    Dir.mktmpdir("asset-response-owner-") do |root|
      File.binwrite(File.join(root, "plain.js"), "owner source")
      File.binwrite(File.join(root, "with-map.js"), "//# sourceMappingURL=unit.map\n")
      load_path = ActionView::SourceAssetLoadPath.new([root], "v1")
      fallback = ->(_env) { [418, {"Content-Type" => "text/plain"}, ["unit fallback"]] }
      server = ActionView::SourceAssetResponse.new(fallback, load_path, "/assets/", false)
      hash = Digest::SHA1.hexdigest("owner sourcev1")[0, 8]
      env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/plain-#{hash}.js"}
      response = server.call(env)
      assert_equal 200, response[0]
      assert_equal ["owner source"], response[2]
      assert_equal "text/javascript", response[1]["Content-Type"]
      assert_equal [], server.call(env.merge("REQUEST_METHOD" => "HEAD"))[2]
      assert_equal 404, server.call(env.merge("PATH_INFO" => "/assets/plain-bad00000.js"))[0]
      assert_equal 418, server.call(env.merge("REQUEST_METHOD" => "POST"))[0]
      assert_raises(ArgumentError) { ActionView::SourceAssetResponse.new(fallback, load_path, "/assets/", true) }
      long_name = "app-workers-media-optimization-entrypoint-abcdefgh.digested.js"
      File.binwrite(File.join(root, long_name), "long genuine-shape unit filename")
      long_env = {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/#{long_name}"}
      long_server = ActionView::SourceAssetResponse.new(fallback, ActionView::SourceAssetLoadPath.new([root], "v1"), "/assets/", false)
      assert_equal 200, long_server.call(long_env)[0]
      refreshed = ActionView::SourceAssetResponse.new(fallback, load_path, "/assets/", true, "null")
      assert_equal ["owner source"], refreshed.call(env)[2]
      File.binwrite(File.join(root, "plain.js"), "changed owner source")
      assert_equal 404, refreshed.call(env)[0]
      fresh_hash = Digest::SHA1.hexdigest("changed owner sourcev1")[0, 8]
      assert_equal ["changed owner source"], refreshed.call(env.merge("PATH_INFO" => "/assets/plain-#{fresh_hash}.js"))[2]
      asset = load_path.find("with-map.js")
      assert_raises(ArgumentError) { asset.compiled_content }
    end
  end
end

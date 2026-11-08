# frozen_string_literal: true
require "minitest/autorun"
require_relative "../../action_dispatch/content_security_policy"

class ContentSecurityPolicyTest < Minitest::Test
  def test_dsl_mapping_deletion_flags_order_and_copy
    policy = ActionDispatch::ContentSecurityPolicy.new
    policy.set_source_directive("upgrade-insecure-requests", [])
    policy.set_source_directive("script-src", [:self, :strict_dynamic, "sha256-YWJj", "'nonce-unit'"])
    policy.set_source_directive("object-src", [:none])
    assert_equal "upgrade-insecure-requests; script-src 'self' 'strict-dynamic' 'sha256-YWJj' 'nonce-unit'; object-src 'none'", policy.build
    copy = policy.dup
    copy.set_source_directive("script-src", [])
    copy.set_flag_directive("upgrade-insecure-requests", false)
    assert_equal "object-src 'none'", copy.build
    assert policy.flag_directive?("upgrade-insecure-requests")
    assert_equal ["'self'", "'strict-dynamic'", "'sha256-YWJj'", "'nonce-unit'"], policy["script-src"]
    policy.set_source_directive("report-uri", ["sha256-not-a-hash-source-here"])
    assert policy.build.end_with?("report-uri sha256-not-a-hash-source-here")
    policy.set_source_directive("report-uri", [:self])
    assert policy.build.end_with?("report-uri self")
    assert_raises(ArgumentError) { policy.set_source_directive("report-uri", []) }
    assert_raises(ArgumentError) { policy.set_source_directive("report-uri", ["/one", "/two"]) }
    assert_raises(ArgumentError) { policy.set_source_directive("report-uri", [7]) }
    assert_raises(ArgumentError) { policy.set_source_directive("unknown", ["x"]) }
    assert_raises(ArgumentError) { policy.set_source_directive("script-src", [:unknown]) }
    assert_raises(ArgumentError) { policy.set_source_directive("upgrade-insecure-requests", ["x"]) }
  end

  def test_validation_is_at_serialization_and_reports_specific_error
    ["bad source", "bad;source", "bad\nsource", "bad\u00a0source"].each do |source|
      policy = ActionDispatch::ContentSecurityPolicy.new
      policy.set_source_directive("report-uri", [source])
      error = assert_raises(ActionDispatch::ContentSecurityPolicy::InvalidDirectiveError) { policy.build }
      assert error.message.start_with?("Invalid Content Security Policy report-uri:")
    end
    policy = ActionDispatch::ContentSecurityPolicy.new
    policy.set_directive("script-src", ["'self'"])
    assert_equal "script-src 'self'", policy.build
    policy["script-src"] = []
    assert_equal "script-src ", policy.build # distinct from empty DSL deletion
  end
end

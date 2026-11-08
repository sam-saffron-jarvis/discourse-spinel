# frozen_string_literal: true
require "minitest/autorun"
require_relative "../../action_view/html_fragment"

class HtmlFragmentTest < Minitest::Test
  def test_explicit_trust_and_idempotent_marking
    fragment = ActionView::HtmlFragment.new("<b>trusted</b>")
    assert fragment.html_safe?
    assert_same fragment, fragment.html_safe
    assert_instance_of String, fragment.to_s
    assert_equal "<b>trusted</b>", fragment.to_s
  end

  def test_mutating_input_or_returned_string_does_not_change_trusted_value
    text = +"<b>trusted</b>"
    fragment = ActionView::HtmlFragment.new(text)
    text.replace("<script>input changed</script>")
    returned = fragment.to_s
    returned.replace("<script>returned value changed</script>")
    assert_equal "<b>trusted</b>", fragment.to_s
    refute_same returned, fragment.to_s
  end
end

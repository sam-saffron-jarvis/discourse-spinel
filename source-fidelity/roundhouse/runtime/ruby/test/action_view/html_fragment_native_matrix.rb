# frozen_string_literal: true
# Native/CRuby owner regression loaded by the isolated helper compile-and-run
# test, without the rest of ActionView or an application/request.
input = +"<em>owner regression</em>"
fragment = ActionView::HtmlFragment.new(input)
input << "input mutation"
returned = fragment.to_s
returned << "returned-string mutation"
raise "trusted fragment aliased mutable input/output" unless fragment.to_s == "<em>owner regression</em>"
raise "trusted fragment type lost" unless fragment.is_a?(ActionView::HtmlFragment) && fragment.html_safe?
raise "trust marking is not idempotent" unless fragment.html_safe.equal?(fragment)
raise "string conversion type changed" unless fragment.to_s.is_a?(String)

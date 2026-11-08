# frozen_string_literal: true
# DB/cache-free UNIT of the genuine projected actor and real framework objects.
require "base64"
require "json"
require_relative "emitted/runtime/action_controller/cookies"
require_relative "emitted/runtime/action_dispatch/session"
require_relative "emitted/runtime/action_dispatch/request"
require_relative "emitted/app/models/auth"
require_relative "emitted/app/models/auth/default_current_user_provider"
# Rack envs contain nullable values, unlike a String-only convenience fixture.
env = {"PATH_INFO" => "/latest.json", "_DISCOURSE_BAD_TOKEN" => nil}
provider = Auth::DefaultCurrentUserProvider.new(env)
raise "real anonymous actor changed" unless provider.current_user.nil?
session = ActionDispatch::Session.new
cookies = ActionController::CookieJar.new({})
provider.refresh_session(nil, session, cookies)
raise "anonymous refresh created a cookie" unless cookies.pending.empty?
token_name = Auth::DefaultCurrentUserProvider::TOKEN_COOKIE
stale = ActionController::CookieJar.new({token_name => "stale-unit-token"})
provider.refresh_session(nil, session, stale)
raise "source stale-cookie deletion omitted" unless stale.pending.key?(token_name) && stale.pending[token_name] == ""
begin
  provider.refresh_session("unsupported-unit-actor", session, cookies)
  raise "authenticated session accepted"
rescue ArgumentError => error
  raise unless error.message.include?("unsupported authenticated session")
end
puts "PASS real actor refresh through concrete session/cookie objects, no new anonymous cookie, stale deletion and authenticated refusal"

# frozen_string_literal: true
require "json"

class ProfileCallLeaf
  attr_reader :calls, :headers, :body
  def initialize(headers)
    @calls = 0
    @headers = headers
    @body = ["original leaf body"]
  end
  def call(env)
    @calls += 1
    [200, @headers, @body]
  end
end

def profile_middleware(name, leaf)
  case name
  when "auth" then Middleware::OmniauthBypassMiddleware.new(leaf)
  when "avatar" then Middleware::MissingAvatars.new(leaf)
  when "csp" then ContentSecurityPolicy::Middleware.new(leaf)
  when "crawler" then Middleware::CrawlerHooks.new(leaf)
  when "head" then Rack::Head.new(leaf)
  else Rack::MethodOverride.new(leaf)
  end
end

names = %w[auth avatar csp crawler head override]
names.each do |name|
  headers = {"Content-Type" => "application/json", "Other" => "preserved"}
  headers["X-Discourse-Crawler-View"] = "true" if name == "crawler"
  leaf = ProfileCallLeaf.new(headers)
  env = {"PATH_INFO" => "/latest.json", "REQUEST_METHOD" => "GET", "rack.url_scheme" => "http", "SERVER_NAME" => "localhost", "SERVER_PORT" => "3000"}
  response = profile_middleware(name, leaf).call(env)
  raise "JSON path entered optional feature or lost body" unless response == [200, headers, ["original leaf body"]] && leaf.calls == 1
  raise "transparent header/body identity changed" unless response[1].equal?(leaf.headers) && response[2].equal?(leaf.body)
  puts JSON.generate({component: name, response: response, calls: leaf.calls, headers_identity: true, body_identity: true})
end

# Original Discourse fast_blank treats NBSP as PRESENT. In this genuine early
# return branch even an HTML response with an existing policy is unchanged.
["default-src 'self'", "\u00a0"].each do |policy|
  leaf = ProfileCallLeaf.new({"Content-Type" => "text/html", "Content-Security-Policy" => policy})
  response = ContentSecurityPolicy::Middleware.new(leaf).call({})
  raise "existing source CSP policy changed" unless response[1]["Content-Security-Policy"] == policy && leaf.calls == 1
end

# Candidate scope boundaries must EXECUTE refusals. Deliberate omission is an
# unsafe 200 on these same leaves, and therefore cannot pass this scope proof.
if defined?(PortableResponseMiddlewareDeclarations)
  names.each do |name|
    env = {"PATH_INFO" => "/latest.json", "REQUEST_METHOD" => "GET"}
    headers = {"Content-Type" => "application/json"}
    case name
    when "auth" then env["PATH_INFO"] = "/auth/login"
    when "avatar" then env["REQUEST_PATH"] = "/uploads/default/avatars/missing.png"
    when "csp" then headers["Content-Type"] = "text/html"
    when "crawler"
      headers["Content-Type"] = "text/html"
      headers["X-Discourse-Crawler-View"] = "true"
    when "head" then env["REQUEST_METHOD"] = "HEAD"
    else env["REQUEST_METHOD"] = "POST"
    end
    leaf = ProfileCallLeaf.new(headers)
    refused = false
    begin
      profile_middleware(name, leaf).call(env)
    rescue ArgumentError => error
      raise unless error.message.start_with?("unsupported JSON profile")
      refused = true
    end
    raise "optional feature silently admitted" unless refused
    raise "route/method exclusion ran app" if %w[auth avatar override].include?(name) && leaf.calls != 0
    raise "response exclusion dropped original app call" if %w[csp crawler head].include?(name) && leaf.calls != 1
    omitted = ProfileCallLeaf.new(headers)
    raise "omitted guard negative was not unsafe" unless omitted.call(env)[0] == 200
  end
end
puts "PASS actual original/shared/native transparent JSON paths, identities, existing policies and executable excluded-profile/omission controls"

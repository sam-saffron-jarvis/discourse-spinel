# frozen_string_literal: true
require "json"
class HostAuthorizationUnitLeaf
  attr_reader :entered
  def initialize
    @entered = false
  end
  def call(env)
    @entered = true
    [200, {"unit-leaf" => "entered"}, [env["action_dispatch.authorized_host"].to_s]]
  end
end

cases = [["localhost:3000", true], ["a.b.localhost:3000", true], ["one.test", true],
         ["127.0.0.1:3000", true], ["8.8.8.8", true], ["[2001:db8::1]:3000", true],
         ["attacker.invalid", false], ["localhost.evil.invalid", false],
         ["127.0.0.999", false], ["localhost:wrong", false]]
results = []
cases.each do |host, allowed|
  env = {"HTTP_HOST" => host, "SERVER_NAME" => "localhost", "SERVER_PORT" => "3000", "rack.url_scheme" => "http"}
  leaf = HostAuthorizationUnitLeaf.new
  middleware = ActionDispatch::HostAuthorization.new(leaf, PortableHostAuthorizationDeclarations.hosts)
  begin
    response = middleware.call(env)
    raise "original blocked host did not return 403" unless allowed || response[0] == 403
    raise "host authorization did not reach app" if allowed && response[0] != 200
  rescue ArgumentError => error
    raise unless !allowed && error.message == "unsupported blocked-host JSON request profile"
  end
  raise "allow/deny classifier changed" unless leaf.entered == allowed
  authorized = env["action_dispatch.authorized_host"]
  if allowed
    raise "host not normalized before app entry" unless authorized == host.sub(/:\d+$/, "")
  else
    raise "blocked host marked authorized" unless authorized.nil?
    raise "blocked-host env lost" unless env["action_dispatch.blocked_hosts"] == [host]
  end
  results << {host: host, allowed: leaf.entered, authorized_host: authorized, blocked_hosts: env["action_dispatch.blocked_hosts"]}
end

# Live source environment additions must not be an observed/frozen host list.
old = ENV["RAILS_DEVELOPMENT_HOSTS"]
begin
  ENV["RAILS_DEVELOPMENT_HOSTS"] = " extra.invalid , .more.invalid "
  permission = ActionDispatch::HostAuthorization::Permissions.new(PortableHostAuthorizationDeclarations.hosts)
  raise "actual live host additions ignored" unless permission.allows?("extra.invalid:3000") && permission.allows?("x.more.invalid")
  raise "wrong host admitted beside configured name" if permission.allows?("extra.invalid.evil")
ensure
  old ? ENV["RAILS_DEVELOPMENT_HOSTS"] = old : ENV.delete("RAILS_DEVELOPMENT_HOSTS")
end
omitted = HostAuthorizationUnitLeaf.new
omitted_env = {"HTTP_HOST" => "localhost:3000"}
omitted.call(omitted_env)
raise "omitted authorization state accepted" unless omitted_env["action_dispatch.authorized_host"].nil?
puts JSON.generate(results)
puts "PASS actual host permissions, IPv4/IPv6, env scope, blocked-host refusal and omitted/live-config controls"

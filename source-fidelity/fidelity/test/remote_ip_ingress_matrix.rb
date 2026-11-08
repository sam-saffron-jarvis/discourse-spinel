# frozen_string_literal: true
require "json"

def base_ingress(peer)
  {"REQUEST_METHOD" => "GET", "PATH_INFO" => "/latest.json", "REMOTE_ADDR" => peer,
   "HTTP_HOST" => "localhost:3000", "rack.url_scheme" => "http", "SERVER_PORT" => "3000"}
end

["127.0.0.1", "::1"].each do |peer|
  env = base_ingress(peer)
  PortableJsonIngress.validate!(env)
  entered = false
  leaf = lambda do |actual|
    entered = true
    value = actual.fetch("action_dispatch.remote_ip")
    raise "missing real lazy remote IP" unless value.is_a?(ActionDispatch::RemoteIp::GetIp)
    first = value.to_s
    raise "remote IP memoization changed" unless value.to_s == first
    [200, {"peer" => first}, [first]]
  end
  middleware = ActionDispatch::RemoteIp.new(leaf)
  raise "nondefault security configuration" unless middleware.check_ip && middleware.proxies.equal?(ActionDispatch::RemoteIp::TRUSTED_PROXIES)
  response = middleware.call(env)
  raise "peer not computed from actual env" unless entered && response == [200, {"peer" => peer}, [peer]]
  puts JSON.generate({peer: peer, response: response, lazy_class: env["action_dispatch.remote_ip"].class.name})
end

# Test the EXACT generated sanitize_ips body against original Rails, including
# netmasks, maximum prefix, singleton forms and invalid strings. No PG fixtures.
calculator = ActionDispatch::RemoteIp::GetIp.new(nil, true, ActionDispatch::RemoteIp::TRUSTED_PROXIES)
addresses = ["127.0.0.1", "127.0.0.1/32", "127.0.0.1/31", "127.0.0.1/255.255.255.255",
             "127.0.0.1/255.255.255.0", "::1", "::1/128", "::1/127", "::ffff:192.0.2.1",
             "invalid", "127.0.0.999", "10.0.0.1/8"]
puts JSON.generate({singleton_ips: calculator.send(:sanitize_ips, addresses.dup)})

invalid = [{"REMOTE_ADDR" => "192.0.2.1"}, {"REMOTE_ADDR" => nil}, {"REMOTE_ADDR" => "127.0.0.1/32"},
           {"REQUEST_METHOD" => "POST"}, {"PATH_INFO" => "/auth/login"},
           {"HTTP_X_FORWARDED_FOR" => "203.0.113.7"}, {"HTTP_X_FORWARDED_FOR" => nil},
           {"HTTP_CLIENT_IP" => "203.0.113.7"}, {"HTTP_FORWARDED" => "for=203.0.113.7"},
           {"HTTP_X_FORWARDED_HOST" => "attacker.invalid"}, {"HTTP_X_FORWARDED_PROTO" => "https"},
           {"HTTP_IF_NONE_MATCH" => "token"}, {"rack.input" => "body"}, {"rack.hijack" => true},
           {"async.callback" => true}, {"action_dispatch.remote_ip" => "203.0.113.7"}]
invalid.each do |extra|
  env = base_ingress("127.0.0.1").merge(extra)
  entered = false
  begin
    PortableJsonIngress.validate!(env)
    entered = true
    raise "unsupported input admitted"
  rescue ArgumentError => error
    raise "wrong refusal" unless error.message.start_with?("unsupported JSON ingress")
    raise "admission happened after effects" if entered || env.key?("action_dispatch.request_id")
    puts JSON.generate({refused_keys: extra.keys, guard: error.message})
  end
end
%w[QUERY_STRING SCRIPT_NAME SERVER_NAME SERVER_PORT rack.url_scheme action_dispatch.request.parameters arbitrary.server.context].each do |key|
  begin
    PortableJsonIngress.validate_overrides!({key => "untrusted"})
    raise "stale parsed context admitted"
  rescue ArgumentError => error
    raise unless error.message == "unsupported JSON ingress parsed-context override"
  end
end
# Missing middleware isn't accepted merely because a default peer happens to
# equal Request's default field: the lazy middleware object MUST be present.
omitted = base_ingress("::1")
raise "omitted IP middleware was accepted" if omitted.key?("action_dispatch.remote_ip")
puts "PASS real RemoteIp direct-peer algorithm, singleton-range equivalence and fail-before-effects ingress controls"

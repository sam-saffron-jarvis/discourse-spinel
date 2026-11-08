# frozen_string_literal: true
# UNIT-only real profiler RedisStore caller; all writes target this runtime's
# separately owned disposable Valkey. No output feeds a later execution.
require_relative "../compat/framework/rack_mini_profiler_core"
require_relative "../compat/framework/portable_redis_connection"
require_relative "owned_cache_policy"
policy = OwnedCachePolicy.new
if ENV["FIDELITY_CACHE_NEGATIVE"] == "1"
  [["127.0.0.1", 6399], ["127.0.0.1", 5499], ["127.0.0.2", ENV.fetch("FIDELITY_VALKEY_PORT").to_i],
   ["127.0.0.1", ENV.fetch("FIDELITY_VALKEY_PORT").to_i + 1]].each do |host, port|
    begin
      PortableRedisConnection.new(host, port, policy, policy)
      raise "unowned endpoint reached transport"
    rescue ArgumentError
    end
  end
  puts "PASS all protected/unknown cache endpoints rejected before transport"
else
  connection = policy.connect
  begin
    store = Rack::MiniProfiler::RedisStore.new(connection: connection, expires_in: 60)
    env = {"SERVER_NAME" => "localhost", "SERVER_PORT" => "3000", "SCRIPT_NAME" => "", "REQUEST_METHOD" => "GET", "PATH_INFO" => "/latest.json", "QUERY_STRING" => "page=1"}
    Rack::MiniProfiler.create_current(env)
    page = Rack::MiniProfiler.current.page_struct
    page[:user] = Digest::MD5.hexdigest("127.0.0.1")
    page[:root].add_sql("SELECT '<owned&effect>'", 0.5, page)
    page[:root].record_time(1.25)
    store.save(page)
    store.set_unviewed(page[:user], page[:id])
    restored = store.load(page[:id])
    raise "missing actual stored profiler page" unless restored[:id] == page[:id] && restored[:root][:duration_milliseconds] == 1.25
    raise "real unviewed set did not retain current ID" unless store.get_unviewed_ids(page[:user]) == [page[:id]]
    ttl = connection.ttl("MPRedisStore" + page[:id])
    raise "profiler TTL not real" unless ttl > 0 && ttl <= 60
    File.binwrite(ENV.fetch("FIDELITY_CACHE_MARSHAL_DUMP"), connection.get("MPRedisStore" + page[:id]))
    Rack::MiniProfiler.current = nil
    puts "PASS actual profiler5 Marshal SETEX/load/unviewed/TTL on owned isolated Valkey"
  ensure
    connection.close
  end
end

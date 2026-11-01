require_relative "../lib/message_bus"

class BusRedis
  attr_reader :commands
  def initialize(last_ids, messages)
    @ids = last_ids
    @messages = messages
    @commands = []
  end
  def command(args)
    @commands << args
    case args[0]
    when "MGET" then @ids
    when "ZRANGEBYSCORE" then @messages
    else raise "non-read-only bus command"
    end
  end
end

def check(value, label)
  raise label unless value
  puts label
end

def transport(channel, id, data)
  "#{id + 100}|#{id}|#{channel.gsub('|', '$$123$$')}|#{JSON.generate(data)}"
end

bus = NativeMessageBus.new
subscriptions = bus.parse("%2Flatest=-1&%2Fsite%2Fbanner=-1&__seq=1")
redis = BusRedis.new(["12", nil], [])
initial = bus.poll(subscriptions, "abcdef", redis)
check(initial == [{ "global_id" => -1, "message_id" => -1, "channel" => "/__status", "data" => { "/latest" => 12, "/site/banner" => 0 } }], "message bus initial status uses live last IDs")
check(redis.commands[0] == ["MGET", "__mb_backlog_id_n_/latest$|$default", "__mb_backlog_id_n_/site/banner$|$default"], "message bus uses actual logical site namespace")
channel = "/latest$|$default"
rows = [
  transport(channel, 1, { "data" => { "topic_id" => 9 } }),
  transport(channel, 2, { "data" => "private-user", "user_ids" => [7] }),
  transport(channel, 3, { "data" => "private-group", "group_ids" => [3] }),
  transport(channel, 4, { "data" => "other-client", "client_ids" => ["other"] }),
  transport(channel, 5, { "data" => "anonymous-group", "group_ids" => [4] }),
]
redis = BusRedis.new(["5"], rows)
result = bus.poll({ "/latest" => "0" }, "abcdef", redis)
check(result.map { |m| m["data"] } == [{ "topic_id" => 9 }, "anonymous-group", { "/latest" => 5 }], "message bus excludes private user group and client messages and advances status")
check(redis.commands.last[2] == "1" && result[0]["channel"] == "/latest" && result[0]["message_id"] == 1, "message bus decodes actual transport and backlog position")
redis = BusRedis.new(["5"], [])
bus.poll({ "/latest" => "-3" }, "abcdef", redis)
check(redis.commands.last[2] == "4", "message bus relative backlog positions")
check(bus.poll({ "/latest" => "5" }, "abcdef", BusRedis.new(["5"], [])).empty?, "message bus empty response only when live position is current")
rejected = 0
["%2Fpolls%2Fprivate=-1", "%2Flatest=bad", "%2Flatest=0&%2Flatest=1", "%2Flatest=1%0D%0ASET"].each do |body|
  begin
    bus.parse(body)
  rescue
    rejected += 1
  end
end
check(rejected == 4, "message bus rejects unsupported channels duplicate subscriptions and malformed positions")
redis = NativeValkey.new
begin
  check(redis.command(["EXISTS", "default:readonly_mode"]).is_a?(Integer), "native Valkey reads task-owned DB0")
  rejected_write = false
  begin
    redis.command(["SET", "never-written", "forbidden"])
  rescue => error
    rejected_write = error.message == "non-read-only Valkey command"
  end
  check(rejected_write, "native Valkey rejects write commands before sending bytes")
ensure
  redis.close
end

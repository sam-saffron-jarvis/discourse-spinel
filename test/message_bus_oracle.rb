# Verification only: actual message_bus 5.0.0 Client/backlog against the same task
# Valkey, anonymous identity and live channel positions as the native adapter.
# Never a serving path. No publishing, subscriptions/listeners, cache writes or DB writes.
require "json"
require_relative "../lib/message_bus"
abort "wrong task database" unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"
abort "wrong task Valkey" unless ENV["REDIS_URL"] == "redis://127.0.0.1:6399/0"

comparisons = []
ActiveRecord::Base.transaction do
  ActiveRecord::Base.connection.execute("SET TRANSACTION READ ONLY")
  topic_ids = Topic.where(deleted_at: nil, archetype: "regular").order(:id).to_a.select { |topic| Guardian.new.can_see?(topic) }.first(3).map(&:id)
  abort "topic bus oracle needs real public topics" if topic_ids.empty?
  [-1, 0, -3, 999999999].each do |position|
    channels = NativeMessageBus::CHANNELS + topic_ids.map { |id| "/topic/#{id}" }
    payload = URI.encode_www_form(channels.to_h { |channel| [channel, position.to_s] })
    native = JSON.parse(NativeMessageBus.new(ActiveRecord::Base.connection.raw_connection).call(payload, "nativeoracle"))
    client = MessageBus::Client.new(message_bus: MessageBus, client_id: "nativeoracle", user_id: nil, site_id: "default", group_ids: [Group::AUTO_GROUPS[:anonymous_users]])
    channels.each { |channel| client.subscribe(channel, position) }
    actual = JSON.parse(MessageBus::Rack::Middleware.backlog_to_json(client.backlog))
    abort "native MessageBus mismatch at position #{position}" unless native == actual
    comparisons << { position: position, channels: channels, message_count: native.length, exact_match: true }
  end
end
puts JSON.pretty_generate(read_only: true, anonymous_group_id: Group::AUTO_GROUPS[:anonymous_users], comparisons: comparisons)

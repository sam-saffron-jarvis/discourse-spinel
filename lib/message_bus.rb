# frozen_string_literal: true
# SELECT-equivalent adaptation of message_bus 5.0.0 Client#backlog/#allowed? and
# Redis backlog reads, for observed guest /latest channels only. Synchronous short
# polling, no hijack/chunking/writes/background listeners. Not a canned [] shim.
require "json"
require "uri"
require_relative "valkey"
require_relative "topic"

class NativeMessageBus
  CHANNELS = %w[/latest /delete /recover /destroy /site/banner /file-change /site/read-only /refresh_client /global/asset-version].freeze

  def initialize(conn = nil)
    @conn = conn
  end

  def self.channel_allowed?(channel)
    CHANNELS.include?(channel) || channel.match?(/\A\/topic\/[1-9]\d{0,9}\z/) || channel.match?(/\A\/private-messages\/unread-indicator\/[1-9]\d{0,9}\z/)
  end

  def parse(body)
    raise "poll body too large" if body.bytesize > 16384
    subscriptions = {}
    URI.decode_www_form(body).each do |pair|
      channel = pair[0]
      value = pair[1]
      next if channel == "__seq"
      raise "unsupported message-bus channel" unless self.class.channel_allowed?(channel)
      raise "duplicate message-bus channel" if subscriptions.key?(channel)
      raise "invalid message-bus position" unless value.empty? || value.match?(/\A-?\d{1,12}\z/)
      subscriptions[channel] = value
    end
    raise "too many message-bus subscriptions" if subscriptions.length > 100
    subscriptions
  end

  def call(body, client_id)
    subscriptions = parse(body)
    subscriptions.keys.each do |channel|
      if channel.start_with?("/topic/")
        id = channel.split("/").last.to_s
        raise "topic channel inaccessible" unless @conn && id.to_i <= 2147483647 && @conn.exec_params(NativeTopic::TOPIC_QUERY, [id]).ntuples == 1
      end
    end
    redis = NativeValkey.new
    begin
      JSON.generate(poll(subscriptions, client_id, redis))
    ensure
      redis.close
    end
  end

  def encoded_channel(channel)
    channel.start_with?("/global/") ? channel : "#{channel}$|$#{NativeValkey::SITE_ID}"
  end

  def poll(subscriptions, client_id, redis)
    return [] if subscriptions.empty?
    channels = subscriptions.keys
    ids = redis.command(["MGET"] + channels.map { |channel| "__mb_backlog_id_n_#{encoded_channel(channel)}" })
    status = {}
    messages = []
    channels.each_with_index do |channel, index|
      last_bus_id = ids[index].to_s.to_i
      value = subscriptions[channel]
      last_client_id = value.empty? ? last_bus_id : value.to_i
      if last_client_id < -1
        last_client_id = [last_bus_id + last_client_id + 1, 0].max
      elsif last_client_id == -1 || last_client_id > last_bus_id
        status[channel] = last_bus_id
        next
      elsif last_client_id == last_bus_id
        next
      end
      encoded = encoded_channel(channel)
      backlog = redis.command(["ZRANGEBYSCORE", "__mb_backlog_n_#{encoded}", (last_client_id + 1).to_s, "+inf", "LIMIT", "0", "1001"])
      raise "message-bus backlog limit exceeded" if backlog.length > 1000
      backlog.each do |raw|
        parts = raw.split("|", 4)
        raise "invalid message-bus transport" unless parts.length == 4 && parts[2].to_s.gsub("$$123$$", "|") == encoded
        data = JSON.parse(parts[3])
        if allowed?(data, client_id)
          messages << { "global_id" => parts[0].to_i, "message_id" => parts[1].to_i, "channel" => channel, "data" => data["data"] }
        else
          status[channel] = last_bus_id
        end
      end
    end
    messages << { "global_id" => -1, "message_id" => -1, "channel" => "/__status", "data" => status } unless status.empty?
    messages
  end

  def allowed?(data, client_id)
    clients = data["client_ids"]
    users = data["user_ids"]
    groups = data["group_ids"]
    client_allowed = clients.nil? || clients.empty? || clients.include?(client_id)
    has_users = users && !users.empty?
    has_groups = groups && !groups.empty?
    # Discourse's actual anonymous pseudogroup is Group::AUTO_GROUPS[:anonymous_users] = 4.
    client_allowed && ((has_users && users.include?(nil)) || (has_groups && groups.include?(4)) || (!has_users && !has_groups))
  end
end

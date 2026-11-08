# frozen_string_literal: true
# TEST-only per-runtime owned fixture policy. Endpoint metadata is configuration,
# never captured oracle results. No shared/unknown endpoint is dispatched to.
require "json"
require "digest"
class OwnedCachePolicy
  attr_reader :saved_profile_id, :processing_during_profile_save, :profile_save_count

  def initialize
    @saved_profile_id = +""
    @processing_during_profile_save = nil
    @profile_save_count = 0
    @host = ENV.fetch("FIDELITY_VALKEY_HOST")
    @port = ENV.fetch("FIDELITY_VALKEY_PORT").to_i
    @pid = ENV.fetch("FIDELITY_VALKEY_PID").to_i
    @path = ENV.fetch("FIDELITY_VALKEY_EVIDENCE")
    @owner = ENV.fetch("FIDELITY_CACHE_OWNER_PID").to_i
  end

  def check!(host, port)
    raise ArgumentError, "protected/unknown cache endpoint" unless host == "127.0.0.1" && host == @host && port == @port && port != 6399 && port != 5499
    evidence = JSON.parse(File.read(@path))
    config = evidence["config"]
    raise ArgumentError, "cache fixture is not live/owned" unless evidence["status"] == "ready" && evidence["pid"] == @pid && evidence["info_process_id"] == @pid && evidence["host"] == host && evidence["port"] == port
    raise ArgumentError, "cache fixture is not disposable loopback-only" unless config["bind"] == [host] && config["port"] == port && config["loopback_only"] == true && config["save"] == "" && config["appendonly"] == "no" && config["protected_mode"] == true
    status = File.read("/proc/#{@pid}/status")
    parent = status.split("\n").find { |line| line.start_with?("PPid:") }.to_s.split.last.to_i
    raise ArgumentError, "fixture is not the runner's child" unless parent == @owner && @owner > 0
    true
  end

  def observe(command, response)
    name = command[0].to_s.upcase
    if name == "SETEX" && /\AMPRedisStore[0-9a-z]{1,20}\z/.match?(command[1].to_s)
      # Observe only AFTER the actual successful write reply. This test output
      # does not feed the application, query, profiler or stored data.
      @saved_profile_id = Marshal.load(command[3])[:id]
      @processing_during_profile_save = Thread.current["discourse.processing_request"]
      @profile_save_count += 1
    end
    return if %w[GET MGET EXISTS TTL INFO CONFIG ZREVRANGEBYSCORE].include?(name)
    puts "FIDELITY_CACHE_EFFECT " + JSON.generate({command: name, key: command[1].to_s,
      arguments_sha256: Digest::SHA256.hexdigest(PortableRedisConnection.encode(command)),
      response_class: response.class.name, response_sha256: Digest::SHA256.hexdigest(Marshal.dump(response))})
  end

  def connect
    check!(@host, @port)
    connection = PortableRedisConnection.new(@host, @port, self, self)
    info = connection.call(["INFO", "server"])
    actual_pid = info.to_s.split("\n").find { |line| line.start_with?("process_id:") }.to_s.split(":").last.to_i
    unless actual_pid == @pid
      connection.close
      raise ArgumentError, "cache socket owner does not match child"
    end
    connection
  end
end

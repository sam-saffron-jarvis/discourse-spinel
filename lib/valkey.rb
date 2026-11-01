# frozen_string_literal: true
require "socket"

# Read-only RESP adapter for the task-owned Valkey DB0. The logical multisite
# identifier is `default`, not the physical PostgreSQL database name.
class NativeValkey
  SITE_ID = "default"

  def initialize
    @socket = TCPSocket.new("127.0.0.1", 6399)
  end

  def command(args)
    raise "non-read-only Valkey command" unless %w[GET MGET EXISTS ZRANGEBYSCORE].include?(args[0])
    @socket.write("*#{args.size}\r\n" + args.map { |arg| "$#{arg.bytesize}\r\n#{arg}\r\n" }.join)
    read_response
  end

  def read_response
    line = @socket.gets.to_s
    raise "invalid Valkey response" if line.empty?
    number = line[1..-1].to_s.to_i
    case line[0]
    when ":" then number
    when "$"
      return nil if number == -1
      raise "Valkey bulk response too large" if number < 0 || number > 16777216
      value = @socket.read(number).to_s
      raise "truncated Valkey bulk response" unless value.bytesize == number && @socket.read(2) == "\r\n"
      value
    when "*"
      raise "Valkey array response too large" if number < 0 || number > 10000
      Array.new(number) { read_response }
    else
      raise "Valkey read failed"
    end
  end

  def close
    @socket.close
  end
end

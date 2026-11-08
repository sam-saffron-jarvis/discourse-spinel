# frozen_string_literal: true
require "socket"

# Shared Ruby RESP2 transport for explicitly injected cache connections. Not a
# topic/query backend. The mandatory endpoint policy is checked BEFORE opening
# a socket and again before every command; no implicit URL, auth or fallback.
class PortableRedisConnection
  COMMANDS = %w[GET MGET SETEX EXISTS TTL ZADD EXPIRE ZREMRANGEBYSCORE ZREVRANGEBYSCORE DEL INFO CONFIG].freeze

  def initialize(host, port, endpoint_policy, observer)
    @host = host
    @port = port
    @endpoint_policy = endpoint_policy
    @observer = observer
    @mutex = Mutex.new
    @socket = nil
    @endpoint_policy.check!(@host, @port)
    @socket = TCPSocket.new(@host, @port)
  end

  def self.encode(command)
    data = +"*#{command.length}\r\n"
    command.each do |part|
      bytes = part.to_s
      data << "$#{bytes.bytesize}\r\n" << bytes << "\r\n"
    end
    data
  end

  def call(command)
    raise ArgumentError, "empty Redis command" if command.empty?
    name = command[0].to_s.upcase
    raise ArgumentError, "unsupported cache command #{name}" unless COMMANDS.include?(name)
    @endpoint_policy.check!(@host, @port)
    @mutex.synchronize do
      raise IOError, "closed cache connection" if @socket.nil?
      data = PortableRedisConnection.encode(command)
      position = 0
      while position < data.bytesize
        written = @socket.write(data.byteslice(position, data.bytesize - position))
        raise IOError, "cache write did not progress" unless written > 0
        position += written
      end
      response = read_reply
      @observer.observe(command, response)
      response
    end
  end

  def read_bytes(length)
    raise IOError, "closed cache connection" if @socket.nil?
    bytes = +""
    while bytes.bytesize < length
      part = @socket.read(length - bytes.bytesize)
      raise EOFError, "short Redis reply" if part.nil? || part.empty?
      bytes << part
    end
    bytes
  end

  def read_reply
    raise IOError, "closed cache connection" if @socket.nil?
    line = @socket.gets
    raise EOFError, "missing Redis reply" unless line && line.end_with?("\r\n")
    value = line.byteslice(1, line.bytesize - 3)
    case line.byteslice(0, 1)
    when "+" then value
    when ":" then value.to_i
    when "-" then raise IOError, "Redis error: #{value}"
    when "$"
      length = value.to_i
      return nil if length == -1
      raise IOError, "invalid Redis bulk length" if length < 0
      data = read_bytes(length)
      raise IOError, "invalid Redis bulk terminator" unless read_bytes(2) == "\r\n"
      data
    when "*"
      length = value.to_i
      return nil if length == -1
      raise IOError, "invalid Redis array length" if length < 0
      values = []
      length.times { values << read_reply }
      values
    else
      raise IOError, "unsupported Redis reply type"
    end
  end

  def get(key)
    call(["GET", key])
  end

  def mget(*keys)
    call(["MGET", *keys])
  end

  def setex(key, seconds, value)
    call(["SETEX", key, seconds, value])
  end

  def ttl(key)
    call(["TTL", key])
  end

  def zadd(key, score, member)
    call(["ZADD", key, score, member])
  end

  def expire(key, seconds)
    call(["EXPIRE", key, seconds])
  end

  def zremrangebyscore(key, minimum, maximum)
    call(["ZREMRANGEBYSCORE", key, minimum, maximum])
  end

  def zrevrangebyscore(key, maximum, minimum)
    call(["ZREVRANGEBYSCORE", key, maximum, minimum])
  end

  def del(key)
    call(["DEL", key])
  end

  def close
    @socket.close unless @socket.nil?
    @socket = nil
  end
end

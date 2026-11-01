# frozen_string_literal: true
# Native HTTP/PG runtime adapter, not a Discourse controller or Rails proxy.
require "socket"
require "pg"
require "uri"
require "json"
require_relative "../lib/latest"

url = ENV.fetch("DATABASE_URL")
raise "unexpected Valkey URL" unless ENV.fetch("REDIS_URL") == "redis://127.0.0.1:6399/0"
uri = URI.parse(url)
raise "unexpected database target" unless uri.scheme == "postgres" && uri.host == "127.0.0.1" && uri.port == 5499 && uri.path == "/discourse_development" && uri.user == "discourse" && uri.query.nil? && uri.fragment.nil?
conn = PG.connect(uri.host.to_s, uri.port, uri.path[1..-1].to_s, uri.user.to_s, uri.password.to_s)
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")
conn.exec("SET TIME ZONE 'UTC'")
emoji_map = JSON.parse(File.read("data/emoji-unicode.json"))
latest = NativeLatest.new(conn, emoji_map)
port = ENV.fetch("PORT", "3499").to_i
raise "unexpected listener port" unless port == 3498 || port == 3499
server = TCPServer.new("127.0.0.1", port)
puts "native discourse minimal listening on 127.0.0.1:#{port}"
loop do
  client = server.accept
  begin
    line = client.gets.to_s
    bytes = line.bytesize
    wants_json = false
    while (header = client.gets)
      downcased = header.downcase
      wants_json = true if (downcased.start_with?("accept:") && downcased.include?("application/json")) || (downcased.start_with?("x-requested-with:") && downcased.include?("xmlhttprequest"))
      bytes += header.bytesize
      raise "request headers too large" if bytes > 16384
      break if header == "\r\n" || header == "\n"
    end
    parts = line.split(" ")
    target = parts[1].to_s
    path = target.split("?", 2)[0].to_s
    query = target.split("?", 2)[1].to_s
    status = "200 OK"
    body = ""
    if parts[0] != "GET"
      status = "405 Method Not Allowed"
      body = JSON.generate({ "error" => "only anonymous GET is supported" })
    elsif path == "/srv/status" && query.empty?
      conn.exec("SELECT 1")
      body = JSON.generate({ "status" => "ok", "database" => "read-only", "frontend" => "not implemented" })
    elsif path == "/latest.json" || (path == "/latest" && wants_json)
      # Discourse pagination URLs omit .json, but XHR/Accept requests are JSON.
      normalized_query = query.sub(/\Ano_definitions=true&/, "").sub(/&no_definitions=true\z/, "")
      page = 0
      if normalized_query.empty?
        body = latest.call(page)
      elsif normalized_query.bytesize <= 9 && normalized_query.match?(/\Apage=\d+\z/) && normalized_query[5..-1].to_s.to_i <= 2000
        page = normalized_query[5..-1].to_s.to_i
        body = latest.call(page)
      else
        status = "400 Bad Request"
        body = JSON.generate({ "error" => "only the page parameter (0..2000) is supported" })
      end
    elsif path == "/latest" || path == "/"
      status = "501 Not Implemented"
      body = JSON.generate({ "error" => "actual Discourse frontend bootstrap/assets not yet integrated", "native_api" => "/latest.json" })
    else
      status = "404 Not Found"
      body = JSON.generate({ "error" => "route not implemented" })
    end
  rescue PG::Error => error
    status = "503 Service Unavailable"
    body = JSON.generate({ "error" => "database query failed" })
    warn error.message
  rescue => error
    status = "501 Not Implemented"
    body = JSON.generate({ "error" => error.message })
  end
  begin
    client.write("HTTP/1.1 #{status}\r\nContent-Type: application/json; charset=utf-8\r\nContent-Length: #{body.bytesize}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n#{body}")
  ensure
    client.close
  end
end

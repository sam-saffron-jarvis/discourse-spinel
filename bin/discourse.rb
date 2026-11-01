# frozen_string_literal: true
# Native HTTP/PG runtime adapter, not a Discourse controller or Rails proxy.
require "socket"
require "pg"
require "uri"
require "json"
require_relative "../lib/latest"
require_relative "../lib/surface"
require_relative "../lib/preloads"
require_relative "../lib/avatars"
require_relative "../lib/message_bus"
require_relative "../frontend/native_document"

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
paths = NativePaths.new(ENV.fetch("MINIMAL_BASE_URI", ""))
preloader = NativePreloads.new(conn)
avatars = NativeAvatars.new(conn, paths)
message_bus = NativeMessageBus.new
document = NativeDocument.new(paths.base_uri)
origin = ENV.fetch("MINIMAL_ORIGIN", "http://127.0.0.1:#{port}")
server = TCPServer.new("127.0.0.1", port)
puts "native discourse minimal listening on 127.0.0.1:#{port}"
loop do
  client = server.accept
  content_type = "application/json; charset=utf-8"
  begin
    # Chromium may preconnect without sending a request. Do not let an idle
    # speculative connection block the single small native listener forever.
    unless IO.select([client], nil, nil, 2)
      client.close
      next
    end
    line = client.gets.to_s
    if line.empty?
      client.close
      next
    end
    bytes = line.bytesize
    wants_json = false
    content_length = 0
    content_length_seen = false
    request_type = ""
    while (header = client.gets)
      downcased = header.downcase
      if downcased.start_with?("content-length:")
        value = header.split(":", 2)[1].to_s.strip
        raise "invalid content length" unless !content_length_seen && value.match?(/\A\d{1,5}\z/) && value.to_i <= 16384
        content_length_seen = true
        content_length = value.to_i
      end
      raise "chunked requests not supported" if downcased.start_with?("transfer-encoding:")
      request_type = downcased.split(":", 2)[1].to_s.strip if downcased.start_with?("content-type:")
      wants_json = true if (downcased.start_with?("accept:") && downcased.include?("application/json")) || (downcased.start_with?("x-requested-with:") && downcased.include?("xmlhttprequest"))
      bytes += header.bytesize
      raise "request headers too large" if bytes > 16384
      break if header == "\r\n" || header == "\n"
    end
    parts = line.split(" ")
    target = parts[1].to_s
    path = paths.route(target.split("?", 2)[0].to_s)
    query = target.split("?", 2)[1].to_s
    status = "200 OK"
    body = ""
    poll_match = path.match(/\A\/message-bus\/([a-f0-9]{1,64})\/poll\z/)
    if parts[0] == "POST" && poll_match
      if (query.empty? || query == "dlp=t") && request_type.start_with?("application/x-www-form-urlencoded")
        request_body = content_length == 0 ? "" : client.read(content_length).to_s
        raise "truncated poll request" unless request_body.bytesize == content_length
        body = message_bus.call(request_body, poll_match[1].to_s)
      else
        status = "400 Bad Request"
        body = JSON.generate({ "error" => "only anonymous form-encoded short polling is supported" })
      end
    elsif parts[0] != "GET"
      status = "405 Method Not Allowed"
      body = JSON.generate({ "error" => "only anonymous GET is supported" })
    elsif path == "/srv/status" && query.empty?
      conn.exec("SELECT 1")
      body = JSON.generate({ "status" => "ok", "database" => "read-only", "frontend" => "core Ember latest integration; topic pages not implemented" })
    elsif path == "/latest.json" || path == "/latest" || path == "/"
      # Discourse pagination URLs omit .json, but XHR/Accept requests are JSON.
      normalized_query = query.sub(/\Ano_definitions=true&/, "").sub(/&no_definitions=true\z/, "")
      page = 0
      valid_page = normalized_query.empty?
      if normalized_query.bytesize <= 9 && normalized_query.match?(/\Apage=\d+\z/) && normalized_query[5..-1].to_s.to_i <= 2000
        page = normalized_query[5..-1].to_s.to_i
        valid_page = true
      end
      if valid_page
        body = latest.call(page)
        unless paths.base_uri.empty?
          payload = JSON.parse(body)
          if payload["topic_list"].key?("more_topics_url")
            payload["topic_list"]["more_topics_url"] = paths.local_url(payload["topic_list"]["more_topics_url"])
          end
          body = JSON.generate(payload)
        end
        unless path == "/latest.json" || wants_json
          preloads = preloader.call(body)
          body = document.render(preloads, JSON.parse(preloads["siteSettings"]), origin)
          content_type = "text/html; charset=utf-8"
        end
      else
        status = "400 Bad Request"
        body = JSON.generate({ "error" => "only the page parameter (0..2000) is supported" })
      end
    elsif path == "/service-worker.js" && query.empty?
      body = document.render_service_worker(origin)
      content_type = "text/javascript; charset=utf-8"
    elsif (asset = paths.asset(path) || avatars.call(path))
      content_type = asset[0]
      body = asset[1]
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
    client.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\nContent-Length: #{body.bytesize}\r\nCache-Control: no-store\r\nX-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n#{body}")
  ensure
    client.close
  end
end

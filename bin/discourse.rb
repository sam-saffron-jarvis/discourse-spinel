# frozen_string_literal: true
# Native HTTP/PG runtime adapter, not a Discourse controller or Rails proxy.
require "socket"
require "pg"
require "uri"
require "json"
require_relative "../lib/latest"
require_relative "../lib/topic"
require_relative "../lib/reactions"
require_relative "../lib/reaction_summary"
require_relative "../lib/surface"
require_relative "../lib/preloads"
require_relative "../lib/avatars"
require_relative "../lib/message_bus"
require_relative "../frontend/native_document"
require_relative "../lib/mini_profiler"

url = ENV.fetch("DATABASE_URL")
raise "unexpected Valkey URL" unless ENV.fetch("REDIS_URL") == "redis://127.0.0.1:6399/0"
uri = URI.parse(url)
raise "unexpected database target" unless uri.scheme == "postgres" && uri.host == "127.0.0.1" && uri.port == 5499 && uri.path == "/discourse_development" && uri.user == "discourse" && uri.query.nil? && uri.fragment.nil?
conn = PG.connect(uri.host.to_s, uri.port, uri.path[1..-1].to_s, uri.user.to_s, uri.password.to_s)
conn.exec("SET default_transaction_read_only = on")
conn.exec("SET statement_timeout = '5s'")
conn.exec("SET TIME ZONE 'UTC'")
conn = SpinelMiniProfilerConnection.new(conn)
emoji_map = JSON.parse(File.read("data/emoji-unicode.json"))
latest = NativeLatest.new(conn, emoji_map)
topics = NativeTopic.new(conn, emoji_map)
reactions = NativeReactions.new(conn)
reaction_summary = NativeReactionSummary.new(conn)
port = ENV.fetch("PORT", "3499").to_i
raise "unexpected listener port" unless [3498, 3499, 3528, 3529].include?(port)
paths = NativePaths.new(ENV.fetch("MINIMAL_BASE_URI", ""))
profiler = ENV.fetch("MINIMAL_PROFILER", "") == "1" ? NativeMiniProfiler.new(paths.base_uri) : nil
preloader = NativePreloads.new(conn)
avatars = NativeAvatars.new(conn, paths)
message_bus = NativeMessageBus.new(conn)
document = NativeDocument.new(paths.base_uri)
origin = ENV.fetch("MINIMAL_ORIGIN", "http://127.0.0.1:#{port}")
server = TCPServer.new("127.0.0.1", port)
puts "native discourse minimal listening on 127.0.0.1:#{port}"
loop do
  client = server.accept
  content_type = "application/json; charset=utf-8"
  profile_request = nil
  profiler_header = ""
  conn.request = nil
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
    unsupported_summary_auth = false
    content_length = 0
    content_length_seen = false
    request_type = ""
    while (header = client.gets)
      downcased = header.downcase
      # This slice has no authenticated behavior. Never interpret credentials or
      # silently claim an authenticated summary; no header values are retained.
      unsupported_summary_auth = true if downcased.match?(/\A(?:authorization|api-key|api-username|api-user-id|api-user-external-id|user-api-key|user-api-client-id|x-shared-session-key|discourse-logged-in):/)
      unsupported_summary_auth = true if downcased.start_with?("cookie:") && downcased.match?(/(?:[:;]\s*)(?:_t|_forum_session)=[^;\s]+/)
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
    profile_request = profiler.start(path, parts[0].to_s) if profiler
    conn.request = profile_request
    profile_route = nil
    if profiler && path.start_with?(NativeMiniProfiler::PREFIX)
      form = ""
      if parts[0] == "POST"
        raise "invalid profiler content type" unless request_type.start_with?("application/x-www-form-urlencoded")
        form = content_length == 0 ? "" : client.read(content_length).to_s
        raise "truncated profiler request" unless form.bytesize == content_length
      end
      profile_route = profiler.route(parts[0].to_s, path, query, form)
    end
    poll_match = path.match(/\A\/message-bus\/([a-f0-9]{1,64})\/poll\z/)
    if profile_route
      status, content_type, body = profile_route
    elsif parts[0] == "POST" && poll_match
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
      body = JSON.generate({ "status" => "ok", "database" => "read-only", "frontend" => "core Ember latest and anonymous topic integration; bounded serializer contract" })
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
    elsif path.start_with?("/discourse-reactions/posts/") && (path.end_with?("/reactions-users") || path.end_with?("/reactions-users.json"))
      begin
        summary_request = NativeReactionSummaryRequest.new(path, query)
        if unsupported_summary_auth
          status = "403 Forbidden"
          body = JSON.generate({ "error" => "authenticated reaction summaries are not extracted" })
        elsif !path.end_with?(".json") && !wants_json
          status = "501 Not Implemented"
          body = JSON.generate({ "error" => "non-JSON reactions shell is not extracted; use .json or JSON/XHR" })
        else
          code, body = reaction_summary.call(summary_request)
          status = { 200 => "200 OK", 403 => "403 Forbidden", 404 => "404 Not Found" }.fetch(code)
        end
      rescue ArgumentError => error
        status = "400 Bad Request"
        body = JSON.generate({ "error" => error.message })
      end
    elsif path.start_with?("/discourse-reactions/posts/")
      begin
        reaction_request = NativeReactionsRequest.new(path, query)
        if !path.end_with?(".json") && !wants_json
          status = "501 Not Implemented"
          body = JSON.generate({ "error" => "non-JSON reactions shell is not extracted; use .json or JSON/XHR" })
        else
          code, body = reactions.call(reaction_request)
          status = { 200 => "200 OK", 403 => "403 Forbidden", 404 => "404 Not Found" }.fetch(code)
        end
      rescue ArgumentError => error
        status = "400 Bad Request"
        body = JSON.generate({ "error" => error.message })
      end
    elsif path.start_with?("/t/")
      begin
        topic_request = NativeTopicRequest.new(path, query)
        topic_body = topics.call(topic_request.id, topic_request.post_number)
        topic_body = paths.mount_topic(topic_body) unless topic_body.nil?
        if topic_body.nil?
          status = "404 Not Found"
          body = JSON.generate({ "error" => "topic not found or inaccessible" })
        else
          body = topic_body
          unless topic_request.json || wants_json
            preloads = preloader.call(latest.call(0))
            preloads["topic_#{topic_request.id}"] = topic_body
            data = JSON.parse(topic_body)
            body = document.render(preloads, JSON.parse(preloads["siteSettings"]), origin,
              topic: { id: data["id"], slug: data["slug"], title: data["title"] })
            content_type = "text/html; charset=utf-8"
          end
        end
      rescue ArgumentError => error
        status = "400 Bad Request"
        body = JSON.generate({ "error" => error.message })
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
  ensure
    # The server is serial. No state survives successful, failed, or idle requests.
    conn.request = nil
  end
  if profiler && profile_request
    id = profiler.finish(profile_request)
    profiler_header = "X-MiniProfiler-Ids: #{id}\r\n"
    body = profiler.inject(body, id) if content_type == "text/html; charset=utf-8" && status == "200 OK"
  end
  begin
    client.write("HTTP/1.1 #{status}\r\nContent-Type: #{content_type}\r\nContent-Length: #{body.bytesize}\r\nCache-Control: no-store\r\n#{profiler_header}X-Content-Type-Options: nosniff\r\nConnection: close\r\n\r\n#{body}")
  ensure
    client.close
  end
end

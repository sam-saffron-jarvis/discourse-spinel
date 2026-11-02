# frozen_string_literal: true
# Opt-in, private-loopback development adapter for the reusable native port.
# The outer authenticated Hub surface remains the access boundary. No cookies,
# credentials or incoming authentication headers are stored or forwarded.
require_relative "reactions"
require_relative "reaction_summary"
require_relative "../vendor/rack-mini-profiler/spinel_mini_profiler"
require_relative "topic"

class NativeMiniProfiler
  PREFIX = "/mini-profiler-resources/"
  ASSETS = { "includes.js" => "text/javascript; charset=utf-8",
    "vendor.js" => "text/javascript; charset=utf-8", "includes.css" => "text/css; charset=utf-8" }.freeze

  def initialize(base_uri)
    @base_uri = base_uri
    @core = SpinelMiniProfiler.new
    @assets = "vendor/rack-mini-profiler/html/"
    @template = File.read(@assets + "profile_handler.js")
    @mobile_style = "<style id=\"native-mini-profiler-layout\">" + File.read("frontend/mini-profiler.css") + "</style>"
  end

  def start(path, method)
    return nil unless method == "GET"
    if path.start_with?("/t/")
      begin
        route = NativeTopicRequest.new(path, "")
      rescue ArgumentError
        return nil
      end
      # Request names reach upstream HTML templates. Keep only canonical numeric
      # route identity, not user-controlled slugs (including Unicode/escapes),
      # while measuring the same actual topic query/document work.
      path = "/t/#{route.id}"
      path += "/#{route.post_number}" if route.post_number > 1
      path += ".json" if route.json
    elsif path.start_with?("/discourse-reactions/posts/")
      summary = path.end_with?("/reactions-users") || path.end_with?("/reactions-users.json")
      begin
        route = summary ? NativeReactionSummaryRequest.new(path, "") : NativeReactionsRequest.new(path, "")
      rescue ArgumentError
        return nil
      end
      # Only canonical numeric identity; never reaction filters or query strings.
      endpoint = summary ? "reactions-users" : "reactions-users-list"
      path = "/discourse-reactions/posts/#{route.id}/#{endpoint}.json"
    elsif !["/", "/latest", "/latest.json", "/srv/status"].include?(path)
      return nil
    end
    @core.start(path, method)
  end

  def finish(request)
    @core.save(request)
  end

  def inject(body, id)
    body.sub("</body>", @mobile_style + @core.bootstrap(@base_uri, id, @template) + "</body>")
  end

  # Exact allowlisted paths, no unescaping/path joining of client-controlled text.
  # Upstream5.0.0 uses POST form results plus GET JS/CSS/vendor assets. Client
  # Performance/probes fields are accepted but deliberately NOT stored/parsed.
  def route(method, path, query, form)
    return nil unless path.start_with?(PREFIX)
    name = path[PREFIX.length..-1].to_s
    if name == "results"
      return ["405 Method Not Allowed", "application/json", '{"error":"GET or POST required"}'] unless method == "GET" || method == "POST"
      input = method == "POST" ? form : query
      ids = input.split("&").select { |part| part.start_with?("id=") }
      id = ids.length == 1 ? ids[0][3..-1].to_s : ""
      return ["400 Bad Request", "application/json", '{"error":"invalid profiler id"}'] unless id.match?(/\A[a-f0-9]{32}\z/)
      result = @core.result(id)
      return ["404 Not Found", "application/json", '{"error":"profile expired or unknown"}'] unless result
      ["200 OK", "application/json; charset=utf-8", result]
    elsif method == "GET" && ASSETS.key?(name) && (query.empty? || query == "v=" + SpinelMiniProfiler::ASSET_VERSION)
      ["200 OK", ASSETS[name], File.binread(@assets + name)]
    else
      ["404 Not Found", "application/json", '{"error":"unsupported profiler resource"}']
    end
  end
end

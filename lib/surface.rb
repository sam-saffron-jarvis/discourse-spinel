# frozen_string_literal: true
# Native boundary adapter. Only staged public assets are reachable; no arbitrary
# source, build evidence, uploads, dot-files or source maps are exposed.
require "json"

class NativePaths
  MIME = {
    ".js" => "text/javascript; charset=utf-8",
    ".css" => "text/css; charset=utf-8",
    ".png" => "image/png", ".jpg" => "image/jpeg", ".jpeg" => "image/jpeg",
    ".svg" => "image/svg+xml", ".webp" => "image/webp", ".gif" => "image/gif",
    ".ico" => "image/x-icon", ".woff" => "font/woff", ".woff2" => "font/woff2",
  }.freeze

  attr_reader :base_uri

  def initialize(base_uri)
    raise "invalid MINIMAL_BASE_URI" unless base_uri.empty? || base_uri.match?(/\A(?:\/[A-Za-z0-9_-]+)+\z/)
    @base_uri = base_uri
    @asset_root = File.realpath("build/assets")
  end

  def route(path)
    # The existing widget strips its mount before forwarding. A direct listener
    # (including the acceptance gate) receives the full mount; support both.
    return "/" if !@base_uri.empty? && path == @base_uri
    return path[@base_uri.length..-1].to_s if !@base_uri.empty? && path.start_with?("#{@base_uri}/")
    path
  end

  def local_url(path)
    "#{@base_uri}#{path}"
  end

  # Task posts were baked at Discourse.base_path == "/". A widget mount is
  # not that persisted cook-time setting. Relocate a RESPONSE COPY only, matching
  # PrettyText.paths[:baseUri]'s local URL deployment role; never rebake/write PG.
  # Root JSON remains byte-identical to the source getters. Mounted cooked HTML
  # is explicitly an adaptation, NOT byte-for-byte root Rails serializer parity.
  def mount_topic(body)
    return body if @base_uri.empty?
    payload = JSON.parse(body)
    payload["post_stream"]["posts"].each do |post|
      post["cooked"] = mount_cooked(post["cooked"].to_s)
    end
    JSON.generate(payload)
  end

  def mount_cooked(html)
    return html if @base_uri.empty?
    # Only actual quoted attributes in HTML tags, not text or script/module code.
    html.gsub(/<[^>]+>/) do |tag|
      tag.gsub(/\s(?:src|href|poster)=["']\/(?!\/)[^"'<>]*["']/) do |attribute|
        separator = attribute.index("=").to_i + 2
        url = attribute[separator...-1].to_s
        if url == @base_uri || url.start_with?("#{@base_uri}/")
          attribute
        else
          attribute[0...separator].to_s + @base_uri + url + attribute[-1].to_s
        end
      end
    end
  end

  def asset(path)
    # Reject encoded separators/dots rather than decoding them; all generated
    # asset URLs use this deliberately narrow canonical ASCII alphabet.
    return nil unless path.match?(/\A\/(?:assets|images|fonts)\/[A-Za-z0-9_\/.\-]+\z/)
    return nil if path[1..-1].to_s.split("/").any? { |part| part.empty? || part.start_with?(".") }
    read_asset(path)
  end

  def read_asset(path)
    relative = if path.start_with?("/assets/")
      path[8..-1].to_s
    elsif path.start_with?("/images/")
      "native/images/#{path[8..-1]}"
    else
      "native/fonts/#{path[7..-1]}"
    end
    mime = MIME[File.extname(relative)]
    return nil unless mime
    candidate = "#{@asset_root}/#{relative}"
    return nil unless File.file?(candidate)
    actual = File.realpath(candidate)
    return nil unless actual.start_with?("#{@asset_root}/")
    [mime, File.binread(actual)]
  end
end

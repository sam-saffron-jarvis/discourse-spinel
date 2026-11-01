# frozen_string_literal: true
# Native boundary adapter. Only staged public assets are reachable; no arbitrary
# source, build evidence, uploads, dot-files or source maps are exposed.
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

# frozen_string_literal: true
# GPL-2.0-or-later. Selected User avatar / BasicUserSerializer / PosterSerializer
# behavior adapted to JSON records; runtime settings provided by NativeSettings.
require "digest"
require "uri"
require_relative "letter_avatar_colors"

module NativeUsers
  def self.avatar_template(user, settings)
    username = user["username"].to_s
    # This adapter does not yet carry the Unicode normalization package.
    raise "unsupported non-ASCII avatar username" unless username.ascii_only?
    if user["id"].to_i == -1 && settings.enabled?("use_site_small_logo_as_system_avatar", true)
      return "/images/discourse-logo-sketch-small.png"
    end
    uploaded_avatar_id = user["uploaded_avatar_id"]
    if !uploaded_avatar_id.nil?
      # UserAvatar.local_avatar_template/version; OptimizedImage::VERSION = 2.
      return "/user_avatar/localhost/#{username.downcase}/{size}/#{uploaded_avatar_id}_2.png"
    end
    normalized_username = username.downcase
    colors = settings.value("restrict_letter_avatar_colors", "")
    hash = Digest::MD5.hexdigest(normalized_username)[0...15].to_i(16)
    color = if colors.empty?
      LetterAvatarColors::COLORS[hash % LetterAvatarColors::COLORS.length].map { |c| c.to_s(16).rjust(2, "0") }.join
    else
      colors.split("|")[hash % colors.split("|").length]
    end
    url = settings.value("external_system_avatars_url", "/letter_avatar_proxy/v4/letter/{first_letter}/{color}/{size}.png")
    raise "unsupported empty external avatar URL" if url.empty?
    url = url.gsub("{color}", color)
    url = url.gsub("{username}", URI.encode_www_form_component(username))
    url = url.gsub("{first_letter}", URI.encode_www_form_component(normalized_username[0].to_s))
    url.gsub("{hostname}", "localhost")
  end

  def self.serialize(user, groups, settings)
    result = { "id" => user["id"], "username" => user["username"], "avatar_template" => avatar_template(user, settings), "trust_level" => user["trust_level"] }
    result["name"] = user["name"] if settings.enabled?("enable_names", true)
    result["admin"] = true if user["admin"] == true
    result["moderator"] = true if user["moderator"] == true
    primary = groups[user["primary_group_id"].to_i]
    result["primary_group_name"] = primary["name"] unless primary.nil?
    flair = groups[user["flair_group_id"].to_i]
    unless flair.nil?
      result["flair_name"] = flair["name"]
      result["flair_group_id"] = user["flair_group_id"]
      %w[flair_url flair_bg_color flair_color].each do |key|
        result[key] = flair[key] unless flair[key].nil? || flair[key] == ""
      end
    end
    result
  end
end

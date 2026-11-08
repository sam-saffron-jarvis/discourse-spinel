# frozen_string_literal: true

module ThemeResolver
  def self.resolve_theme_id(request, guardian, current_user)
    return resolve_latest_json_theme_id(request, guardian, current_user) if request.params["format"].to_s == "json"
    return request.env[:resolved_theme_id] if request.env[:resolved_theme_id] != nil

    theme_id = nil

    if (preview_theme_id = request[:preview_theme_id]&.to_i) &&
         guardian.allow_themes?([preview_theme_id], include_preview: true)
      theme_id = preview_theme_id
    end

    user_option = current_user&.user_option

    if theme_id.blank? && request.cookie_jar[:theme_ids].present?
      ids, seq = request.cookie_jar[:theme_ids]&.split("|")
      id = ids&.split(",")&.map(&:to_i)&.first
      if id.present? && seq && seq.to_i == user_option&.theme_key_seq.to_i
        theme_id = id if guardian.allow_themes?([id])
      end
    end

    if theme_id.blank?
      ids = user_option&.theme_ids || []
      theme_id = ids.first if guardian.allow_themes?(ids)
    end

    if theme_id.blank? && guardian.allow_themes?([SiteSetting.default_theme_id])
      theme_id = SiteSetting.default_theme_id
    end

    request.env[:resolved_theme_id] = theme_id
  end
end
module ThemeResolver
  def self.resolve_latest_json_theme_id(request, guardian, current_user)
    raise ArgumentError, "unsupported authenticated JSON theme profile" unless current_user.nil?
    cached = request.env["discourse.resolved_theme_id"]
    return cached unless cached.nil?
    raise ArgumentError, "unsupported preview JSON theme profile" if request.params.key?("preview_theme_id")
    cookie_header = request.env["HTTP_COOKIE"]
    raise ArgumentError, "unsupported cookie-selected JSON theme profile" unless cookie_header.nil? || cookie_header.empty?
    theme_id = nil
    # Original user_option&.theme_ids || [] under the verified nil user.
    ids = []
    theme_id = ids.first if guardian.allow_themes?(ids)
    if theme_id.blank? && guardian.allow_themes?([SiteSetting.default_theme_id])
      theme_id = SiteSetting.default_theme_id
    end
    request.env["discourse.resolved_theme_id"] = theme_id
  end
end

# frozen_string_literal: true
# Selected UserAvatarsController#show_in_site plus public current-upload lookup.
# No image-processing writes or CDN proxy. See GAPS for original-size and offline
# letter-avatar fallback (the latter is the actual Rails render_blank asset).
require_relative "surface"

class NativeAvatars
  def initialize(conn, paths)
    @conn = conn
    @paths = paths
    @media_root = File.realpath("build/media")
  end

  def call(path)
    if path.match?(/\A\/letter_avatar_proxy\/v4\/letter\/[a-z0-9_]\/[a-f0-9]{6}\/(\d{1,4})\.png\z/) && path.split("/")[-1].to_s.to_i >= 8 && path.split("/")[-1].to_s.to_i <= 1000
      # External avatar CDN use is forbidden by this task. This intentionally
      # follows Rails' disable_proxy?/render_blank behavior, not a fake identity.
      return blank
    end
    match = path.match(/\A\/user_avatar\/localhost\/([a-z0-9_.-]+)\/(\d{1,4})\/(\d{1,10})_2\.png\z/)
    return nil unless match
    username = match[1].to_s
    return nil if username == "." || username == ".."
    size = match[2].to_s.to_i
    upload_id = match[3].to_s
    return blank if size < 8 || size > 1000
    rows = @conn.exec_params(<<~SQL, [username, upload_id, size.to_s])
      SELECT up.url, up.extension,
        (SELECT im.url FROM optimized_images im
         WHERE im.upload_id=up.id AND im.width=$3::integer AND im.height=$3::integer
         ORDER BY im.id DESC LIMIT 1) AS optimized_url
      FROM users u JOIN uploads up ON up.id=u.uploaded_avatar_id
      WHERE u.username_lower=$1 AND up.id=$2::integer AND NOT up.secure
    SQL
    return blank if rows.ntuples == 0
    url = rows.getvalue(0, 2).to_s
    url = rows.getvalue(0, 0).to_s if url.empty?
    return blank unless url.match?(/\A\/uploads\/default\/(?:original|optimized)\/[A-Za-z0-9_\/-]+\.(?:png|jpe?g|gif|webp)\z/)
    filename = "#{@media_root}#{url}"
    return blank unless File.file?(filename)
    actual = File.realpath(filename)
    return blank unless actual.start_with?("#{@media_root}/")
    mime = NativePaths::MIME[File.extname(url)]
    return blank unless mime
    [mime, File.binread(actual)]
  end

  def blank
    @paths.asset("/images/avatar.png")
  end
end

# frozen_string_literal: true
require "ffi"
require "digest"

# Read-only equivalent of the original Vips worker's version operation. This
# binds ONLY the no-argument version-string function, never an image operation.
module PortableAvatarVipsVersion
  extend FFI::Library
  ffi_lib "vips"
  attach_function :vips_version_string, [], :string
end

class PortableLetterAvatarVersion
  # LetterAvatar::VIPS_VERSION from the pinned application source. Library and
  # font hashes below are computed at runtime, NOT captured oracle/version data.
  VIPS_VERSION = 6

  def self.version
    unless SiteSetting.portable_rendering_vips_enabled?
      raise ArgumentError, "unsupported ImageMagick avatar-version profile"
    end
    font = File.expand_path("../config/portable_avatar_source/NotoSans-Regular.woff2", __dir__)
    font_version = Digest::MD5.file(font).hexdigest
    library_version = PortableAvatarVipsVersion.vips_version_string
    "#{VIPS_VERSION}_#{Digest::MD5.hexdigest([library_version, font_version].join("\0"))}"
  end
end

# frozen_string_literal: true

module SiteSettings
  # Actual readonly upload lookup from SiteSettingExtension#setup_methods.
  # The shared store supplies live per-site default/override/config precedence.
  # Fresh Upload reads deliberately do not claim Rails' uploads[] cache effects.
  module PortableUploadReaders
    def logo_small(scoped_to = nil)
      raise PortableUnsupported, "scoped logo_small profile is not supported" unless scoped_to.nil?
      value = portable_store.get_upload_id("logo_small", portable_site)
      Upload.find_by(id: value) if value != Upload::SEEDED_ID_THRESHOLD
    end
  end
end

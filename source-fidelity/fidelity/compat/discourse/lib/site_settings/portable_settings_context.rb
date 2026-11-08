# frozen_string_literal: true

require_relative "portable_core_definitions"

module SiteSettings
  # Explicit bootstrap context for the shared accessors. Native application
  # bootstrap supplies a real provider and site identity; Rails supplies its
  # own current-site routing through PortableRailsExtension's methods instead.
  # No setting value, endpoint or permission is captured here.
  module PortableSettingsContext
    def configure_portable_settings(provider, site)
      raise ArgumentError, "site must not be empty" if site.empty?
      replacement = PortableReadStore.new(PortableCoreDefinitions.build, provider)
      replacement.refresh!(site)
      @portable_store = replacement
      @portable_site = site
      @portable_global_configuration = provider.respond_to?(:global_configuration) ? provider.global_configuration : nil
      nil
    end

    def portable_rendering_hostname
      value = @portable_global_configuration.database_hostname
      raise PortableUnsupported, "presentation hostname must be a String" unless value.is_a?(String)
      value
    end

    def portable_rendering_base_path
      value = @portable_global_configuration.value("relative_url_root")
      value.nil? || value == "" ? "" : value.to_s
    end

    def portable_rendering_vips_enabled?
      @portable_global_configuration.value("enable_vips_image_processing") == true
    end

    # The native translator eagerly compiles the pinned locale resources.
    # Validate the requested compiled locale; there is no lazy loader to fake.
    def portable_prepare_request_locale(locale)
      raise PortableUnsupported, "request locale is not compiled" unless I18n.locale_available?(locale)
      locale
    end

    def portable_reject_anonymous_min_queue_seconds
      value = @portable_global_configuration.value("reject_anonymous_min_queue_seconds")
      unless value.is_a?(Integer) || value.is_a?(Float)
        raise PortableUnsupported, "anonymous request queue threshold must be numeric"
      end
      value.to_f
    end

    def portable_allowed_theme_repos
      value = @portable_global_configuration.value("allowed_theme_repos")
      raise PortableUnsupported, "allowed theme repositories must be a String" unless value.nil? || value.is_a?(String)
      value
    end

    def portable_cors_enabled?
      value = @portable_global_configuration.value("enable_cors")
      unless value.nil? || value == true || value == false
        raise PortableUnsupported, "unsupported non-boolean CORS configuration"
      end
      value == true
    end

    def portable_cors_origin
      value = @portable_global_configuration.value("cors_origin")
      raise PortableUnsupported, "unsupported non-string global CORS origins" unless value.nil? || value.is_a?(String)
      value
    end

    def portable_rendering_asset_host
      @portable_global_configuration.value("cdn_url")
    end

    def portable_avatar_cdn_url(url)
      asset_host = portable_rendering_asset_host
      return url if asset_host.nil? || asset_host == ""
      raise PortableUnsupported, "configured avatar CDN profile needs the complete source URL transformer"
    end

    def portable_store
      @portable_store || raise(PortableUnsupported, "portable settings context is not configured")
    end

    def portable_site
      @portable_site || raise(PortableUnsupported, "portable settings context is not configured")
    end
  end
end

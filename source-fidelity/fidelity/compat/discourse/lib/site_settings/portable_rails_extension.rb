# frozen_string_literal: true

require_relative "portable_core_definitions"
require_relative "portable_settings_context"
require_relative "portable_scalar_readers"
require_relative "portable_pg_provider"

module SiteSettings
  # Transitional application integration, not a replacement for special-setting
  # business logic. Scalar accessors/cache are shared with native Spinel; the
  # original extension still owns metadata, themes, uploads, upcoming changes,
  # client serialization, change subscriptions and security maps.
  module PortableRailsExtension
    def portable_rendering_hostname
      RailsMultisite::ConnectionManagement.current_hostname
    end

    def portable_rendering_base_path
      Discourse.base_path
    end

    def portable_rendering_vips_enabled?
      GlobalSetting.enable_vips_image_processing
    end

    def portable_prepare_request_locale(locale)
      # Original callback prepares the current fallback chain before entering
      # with_locale. Keep the genuine lazy loader on full candidate Rails.
      I18n.ensure_all_loaded!
      locale
    end

    def portable_reject_anonymous_min_queue_seconds
      GlobalSetting.reject_anonymous_min_queue_seconds.to_f
    end

    def portable_allowed_theme_repos
      GlobalSetting.allowed_theme_repos
    end

    def portable_rendering_asset_host
      Discourse.asset_host
    end

    def portable_definitions
      @portable_definitions ||= PortableCoreDefinitions.build
    end

    def portable_scalar_setting?(name)
      @portable_scalar_names ||= portable_definitions.select(&:portable_scalar?).map(&:name) - ["default_locale"]
      @portable_scalar_names.include?(name.to_s)
    end

    def portable_site
      provider.current_site.to_s
    end

    def portable_store
      @portable_store ||= begin
        configuration = PortableGlobalConfiguration.new(
          portable_definitions,
          Rails.root.join("config/discourse_defaults.conf").to_s,
          Rails.root.join("config/discourse.conf").to_s,
        )
        PortableReadStore.new(portable_definitions, PortableRailsProvider.new(self, configuration))
      end
    end

    # Publish the shared scalar snapshot before refreshing special settings:
    # UpcomingChanges reads scalar promotion controls during its own refresh.
    # Preserve the original change-bus subscriptions and clear client/theme/site
    # caches only after both refreshes complete. Cross-cache atomicity is not
    # claimed by this transitional adapter (the store itself publishes atomically).
    def refresh!(refresh_site_settings: true, refresh_theme_site_settings: true, clear_caches: true)
      portable_store.refresh!(portable_site) if refresh_site_settings
      super(refresh_site_settings: refresh_site_settings,
            refresh_theme_site_settings: refresh_theme_site_settings, clear_caches: false)
      if clear_caches
        clear_cache!(expire_theme_site_setting_cache:
          ThemeSiteSetting.can_access_db? && refresh_theme_site_settings)
      end
      nil
    end

    # All persistence entrypoints ultimately pass here. Broader writes are not
    # part of this readonly candidate; do not let special setters bypass that.
    def add_override!(*args, **kwargs)
      raise PortableUnsupported, "settings writes are outside the portable Rails candidate scope"
    end

    protected

    # Generated scalar readers are installed before declarations are loaded.
    # Preserve the original setup for every special or unknown declaration.
    def setup_methods(name)
      super unless portable_scalar_setting?(name)
    end

    def setup_shadowed_methods(name, value)
      super unless portable_scalar_setting?(name)
    end
  end

  class PortableRailsProvider
    def initialize(settings, configuration)
      @settings = settings
      @configuration = configuration
    end

    def check_site!(site)
      unless @settings.provider.current_site.to_s == site
        raise ArgumentError, "portable settings site changed during refresh"
      end
    end

    def all(site)
      check_site!(site)
      connection = ActiveRecord::Base.connection
      unless connection.select_value("SHOW default_transaction_read_only") == "on"
        raise PortableUnsupported, "portable settings provider requires a readonly connection"
      end
      # Retain the real configured application's provider and connection routing.
      @settings.provider.all.map do |row|
        PortableRow.new(row.name.to_s, row.value, row.data_type)
      end
    end

    def global_overrides(site)
      check_site!(site)
      @configuration.overrides(site)
    end
  end
end

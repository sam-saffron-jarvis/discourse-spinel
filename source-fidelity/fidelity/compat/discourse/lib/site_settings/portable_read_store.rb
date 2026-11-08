# frozen_string_literal: true

# Shared application code for the patched/core-no-plugins candidate.
# This is the read-store boundary, NOT yet a complete SiteSetting replacement.
require "json"
require "thread"

module SiteSettings
  class PortableUnsupported < StandardError
  end

  class PortableDefinition
    attr_reader :name, :default_value, :data_type, :options

    def initialize(name, default_value, data_type, options_json)
      @name = name
      # YAML's scalar strings are mutable; generated source literals are not.
      @default_value = default_value.is_a?(String) ? default_value.dup : default_value
      @data_type = data_type
      @options = JSON.parse(options_json)
    end

    def default_for(locale)
      localized = @options["locale_default"]
      if localized.is_a?(Hash) && localized.key?(locale)
        localized[locale]
      else
        @default_value
      end
    end

    def portable_scalar?
      !themeable? && !@options.key?("upcoming_change") &&
        !@options.key?("upcoming_change_default_override") &&
        (!@options.key?("enum") || @options["portable_unwrapped_enum"] == true) &&
        !@options.key?("portable_source_override") && ![17, 18, 28].include?(@data_type)
    end

    def client?
      @options["client"] == true
    end

    def secret?
      @options["secret"] == true
    end

    def hidden?
      @options["hidden"] == true
    end

    def themeable?
      @options["themeable"] == true
    end
  end

  class PortableRow
    attr_reader :name, :value, :data_type

    def initialize(name, value, data_type)
      @name = name
      @value = value
      @data_type = data_type
    end
  end

  # Providers implement all(site) and global_overrides(site). A site is an
  # explicit request/connection identity, not an observed single-site constant.
  # Refresh builds a complete replacement before publication: a provider/type
  # error cannot publish a partially refreshed site or change another site's
  # cache. The caller's refresh block runs AFTER publication, outside the lock.
  class PortableReadStore
    def initialize(definitions, provider)
      @definitions = {}
      definitions.each do |definition|
        raise ArgumentError, "duplicate setting #{definition.name}" if @definitions.key?(definition.name)
        @definitions[definition.name] = definition
      end
      @provider = provider
      @values = {}
      @modified = {}
      @shadows = {}
      @mutex = Mutex.new
    end

    def has_setting?(name)
      @definitions.key?(name.to_s.delete_suffix("?"))
    end

    # Mirrors TypeSupervisor#to_rb_value's wire-value coercions. Unknown IDs
    # are an error, not a guessed string; NULL and empty text stay distinct in
    # types whose original wire contract leaves the value unchanged.
    def coerce(name, value, data_type)
      case data_type
      when 4
        value.to_f
      when 3, 27
        value.to_i
      when 5
        value == true || value == "t" || value == "true"
      when 6
        nil
      when 7
        definition = @definitions[name]
        definition && definition.default_value.is_a?(Integer) ? value.to_i : value.to_s
      when 1, 31, 32, 33
        value.to_s
      else
        raise ArgumentError, "type" unless data_type >= 1 && data_type <= 33
        value
      end
    end

    def refresh!(site)
      raise ArgumentError, "site must not be empty" if site.empty?
      changed = []
      removed = []
      @mutex.synchronize do
        rows = @provider.all(site)
        overrides = {}
        rows.each { |row| overrides[row.name] = coerce(row.name, row.value, row.data_type) }
        locale = overrides["default_locale"]
        locale = "en" if locale.nil? || locale == ""
        defaults = {}
        @definitions.each { |name, definition| defaults[name] = definition.default_for(locale.to_s) }
        replacement = defaults.merge(overrides)
        modified = {}
        overrides.each do |name, value|
          definition = @definitions[name]
          special = definition && (definition.options.key?("upcoming_change") || definition.options.key?("upcoming_change_default_override"))
          modified[name] = value if special || value.to_s != defaults[name].to_s
        end
        shadows = []
        @provider.global_overrides(site).each do |name, value|
          if @definitions.key?(name) && !value.nil? && value != ""
            replacement[name] = value
            shadows << name
          end
        end
        previous = @values[site] || {}
        replacement.each { |name, value| changed << name if !previous.key?(name) || previous[name] != value }
        previous.each_key { |name| removed << name if !replacement.key?(name) }
        @values[site] = replacement
        @modified[site] = modified
        @shadows[site] = shadows
      end
      yield(site, changed, removed) if block_given?
      nil
    end

    def invalidate!(site)
      @mutex.synchronize do
        @values.delete(site)
        @modified.delete(site)
        @shadows.delete(site)
      end
      nil
    end

    # Source upload getter boundary (SiteSettingExtension#setup_methods).
    # Read the real per-site declaration/DB/config ID; this is NOT a scalar
    # getter relaxation and never manufactures an Upload or URL.
    def get_upload_id(name, site)
      name = name.to_s
      definition = @definitions[name]
      raise ArgumentError, "No setting named '#{name}' exists" unless definition
      unless definition.data_type == 18 && !definition.themeable? &&
          !definition.options.key?("upcoming_change") && !definition.options.key?("upcoming_change_default_override")
        raise PortableUnsupported, "#{name} needs its scoped upload contract"
      end
      snapshot = @mutex.synchronize { @values[site] }
      unless snapshot
        refresh!(site)
        snapshot = @mutex.synchronize { @values[site] }
      end
      value = snapshot[name]
      if value.nil?
        refresh!(site)
        value = @mutex.synchronize { @values[site][name] }
      end
      unless value.nil? || value.is_a?(String) || value.is_a?(Integer)
        raise PortableUnsupported, "#{name} has an invalid upload ID type"
      end
      value.nil? ? 0 : value.to_i
    end

    def get(name, site)
      name = name.to_s.delete_suffix("?")
      definition = @definitions[name]
      raise ArgumentError, "No setting named '#{name}' exists" unless definition
      # Special source getters must not silently degrade into raw IDs/strings
      # or ignore theme/upcoming-change/group behaviour. Integration supplies
      # these contracts separately before claiming full SiteSetting support.
      options = definition.options
      unless definition.portable_scalar?
        raise PortableUnsupported, "#{name} needs its source special-getter contract"
      end
      snapshot = @mutex.synchronize { @values[site] }
      unless snapshot
        refresh!(site)
        snapshot = @mutex.synchronize { @values[site] }
      end
      value = snapshot[name]
      if name == "default_locale"
        return value.nil? || value == "" ? "en" : value
      end
      mandatory = options["mandatory_values"]
      value = (mandatory.split("|") | value.to_s.split("|")).join("|") if mandatory.is_a?(String)
      value
    end

    def setting_modified_from_default?(name, site)
      get_snapshot = @mutex.synchronize { @modified[site] }
      unless get_snapshot
        refresh!(site)
        get_snapshot = @mutex.synchronize { @modified[site] }
      end
      get_snapshot.key?(name.to_s)
    end

    def client_settings_hash(site)
      result = {}
      @definitions.each do |name, definition|
        next unless definition.client?
        next if definition.themeable?
        # Secrets and shadowed configuration are never silently serialized.
        # A conflicting client/secret declaration is refused, not leaked.
        raise PortableUnsupported, "client setting #{name} is secret" if definition.secret?
        result[name] = get(name, site)
      end
      result
    end

    def hidden?(name, site)
      shadowed = @mutex.synchronize { @shadows[site] }
      unless shadowed
        refresh!(site)
        shadowed = @mutex.synchronize { @shadows[site] }
      end
      definition = @definitions[name.to_s]
      !!(definition && (definition.hidden? || shadowed.include?(name.to_s)))
    end

    def set(name, value, site)
      raise PortableUnsupported, "settings writes are outside the portable read-store scope"
    end
  end
end

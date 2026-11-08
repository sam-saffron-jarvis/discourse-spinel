# frozen_string_literal: true
require_relative "portable_read_store"

module SiteSettings
  # The source FileProvider/EnvProvider precedence in shared application code.
  # Reads real files/environment on refresh, never a saved effective-settings
  # map. Like GlobalSetting, a present discourse.conf selects the file provider
  # instead of merging arbitrary environment overrides into it.
  class PortableGlobalConfiguration
    def initialize(definitions, defaults_path, configuration_path)
      @names = definitions.map(&:name)
      @defaults_path = defaults_path
      @configuration_path = configuration_path
    end

    def read_file(path)
      values = {}
      return values unless File.exist?(path)
      source = File.read(path)
      if source.include?("<%")
        raise PortableUnsupported, "ERB global configuration needs its source expansion contract"
      end
      source.split("\n").each do |line|
        match = /\A\s*([a-z_]+[a-z0-9_]*)\s*=\s*(\"([^\"]*)\"|'([^']*)'|[^#]*)/.match(line)
        values[match[1].strip] = (match[4] || match[3] || match[2]).strip if match
      end
      values
    end

    def coerce(value)
      return true if value == "true"
      return false if value == "false"
      return value.strip.to_i if value.is_a?(String) && /\A(-?[0-9]+)\z/.match?(value.strip)
      value
    end

    # Preserve BaseProvider#resolve's presence semantics, including its false
    # fallback behaviour, rather than introducing generic truthy/default rules.
    def resolve(current, fallback)
      value = current
      value = fallback if value.nil? || value == "" || value == false
      value = nil if value == "" || value == false
      coerce(value)
    end

    # Same FileProvider/EnvProvider precedence for presentation-only global
    # configuration (hostname, relative_url_root and cdn_url). No captured host.
    def value(name)
      defaults = read_file(@defaults_path)
      file_mode = File.exist?(@configuration_path)
      configured = file_mode ? read_file(@configuration_path) : {}
      fallback = resolve(defaults[name], nil)
      current = file_mode ? configured[name] : ENV["DISCOURSE_" + name.upcase]
      resolve(current, fallback)
    end

    # RailsMultisite.current_hostname uses connection_spec.config[:host_names],
    # NOT GlobalSetting.hostname. This is the pinned config/database.yml's
    # development branch; other routing profiles must bring their real source.
    def database_hostname
      environment = ENV["RAILS_ENV"] || "development"
      raise PortableUnsupported, "unsupported database hostname environment" unless environment == "development"
      multisite = File.join(File.dirname(@defaults_path), "multisite.yml")
      raise PortableUnsupported, "unsupported configured multisite hostname routing" if File.exist?(multisite)
      ENV['DISCOURSE_HOSTNAME'] || 'localhost'
    end

    def overrides(site)
      defaults = read_file(@defaults_path)
      file_mode = File.exist?(@configuration_path)
      configured = file_mode ? read_file(@configuration_path) : {}
      result = {}
      @names.each do |name|
        env_name = "DISCOURSE_" + name.upcase
        present = defaults.key?(name) || (file_mode ? configured.key?(name) : ENV.key?(env_name))
        next unless present
        fallback = resolve(defaults[name], nil)
        current = file_mode ? configured[name] : ENV[env_name]
        result[name] = resolve(current, fallback)
      end
      result
    end
  end
end

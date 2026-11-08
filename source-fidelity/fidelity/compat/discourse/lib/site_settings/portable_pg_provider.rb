# frozen_string_literal: true
require_relative "portable_read_store"
require_relative "portable_global_configuration"

module SiteSettings
  # Production read-only provider. Connections implement the PG result protocol
  # common to the pg gem and spinel-pg; opening/credentials belong to the existing
  # application's connection bootstrap, not this settings cache.
  # Each logical site has its OWN registered connection. Never memoize a single
  # observed site or silently use another site's connection.
  class PortablePgProvider
    attr_reader :global_configuration

    def initialize(connections, global_configuration)
      @connections = connections
      @global_configuration = global_configuration
      @mutex = Mutex.new
    end

    def all(site)
      rows = []
      @mutex.synchronize do
        connection = @connections[site]
        raise ArgumentError, "no settings connection for site #{site}" unless connection
        state = connection.exec("SHOW default_transaction_read_only")
        raise PortableUnsupported, "portable settings provider requires a readonly connection" unless state.getvalue(0, 0) == "on"
        result = connection.exec("SELECT name, data_type, value FROM site_settings")
        result.ntuples.times do |index|
          rows << PortableRow.new(result.getvalue(index, 0).to_s,
                                  result.getvalue(index, 2),
                                  result.getvalue(index, 1).to_i)
        end
      end
      rows
    end

    # Live application configuration, not a saved effective settings snapshot.
    # Read the real configuration provider on every refresh. An unregistered
    # site is an error even when it has no global overrides.
    def global_overrides(site)
      raise ArgumentError, "no settings connection for site #{site}" unless @connections.key?(site)
      @global_configuration.overrides(site)
    end
  end
end

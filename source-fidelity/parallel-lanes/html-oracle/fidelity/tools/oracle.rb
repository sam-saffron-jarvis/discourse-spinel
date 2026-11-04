# frozen_string_literal: true
# Test-only actual Discourse oracle, never a dependency of the native ELF.
# The isolation layer authorizes real cache/logging effects only on the owned
# disposable Valkey fixture and guards every PG connection read-only.
require_relative "oracle_isolation"
at_exit { FidelityOracleIsolation.cleanup_vips! }
raise "oracle must run from Discourse root" unless File.file?("config/environment.rb")
raise "missing read-only PGOPTIONS" unless ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
require File.expand_path("config/environment.rb")
connection = ActiveRecord::Base.connection
raise "wrong database" unless connection.select_value("SELECT current_database()") == "discourse_development"
raise "oracle connection is writable" unless connection.select_value("SHOW default_transaction_read_only") == "on"
raise "wrong PG port" unless connection.select_value("SELECT inet_server_port()") == 5499

if ARGV.first == "schema"
  rows = connection.select_all(<<~SQL).to_a
    SELECT table_name,column_name,data_type,is_nullable,column_default
    FROM information_schema.columns
    WHERE table_schema = 'public' AND table_name IN ('topics', 'categories')
    ORDER BY table_name,ordinal_position
  SQL
  puts "FIDELITY_SCHEMA " + JSON.generate({columns: rows, ignored_columns: {topics: Topic.ignored_columns, categories: Category.ignored_columns},
      topic_default_scopes: Topic.default_scopes.map { |scope| scope.scope.source_location },
      count: Topic.listable_topics.visible.count})
  exit
end

module FidelityDriver
  def self.capture
    log = []
    subscription = ActiveSupport::Notifications.subscribe("sql.active_record") do |*args|
      payload = args.last
      log << payload[:sql] unless payload[:name] == "SCHEMA" || payload[:cached]
    end
    begin
      yield
    ensure
      ActiveSupport::Notifications.unsubscribe(subscription)
    end
    log
  end
  def self.category_loaded(record)
    record.association(:category).loaded?
  end
  def self.encode(value)
    JSON.generate(value)
  end
  def self.timestamp(value)
    value.nil? ? nil : value.utc.strftime("%Y-%m-%dT%H:%M:%S.%6NZ")
  end
end
load File.expand_path(ARGV.fetch(0))
load File.expand_path(ARGV.fetch(1))
original_inputs = %w[app/models/topic.rb app/models/category.rb app/models/concerns/trashable.rb lib/archetype.rb]
original_inputs += JSON.parse(ENV.fetch("FIDELITY_EXTRA_ORIGINAL_INPUTS", "[]"))
original_inputs.each do |path|
  raise "oracle did not load complete original #{path}" unless $LOADED_FEATURES.include?(File.expand_path(path))
end
puts "FIDELITY_ORACLE " + JSON.generate({rails: Rails.version, active_record: ActiveRecord::VERSION::STRING,
    complete_original_files: original_inputs.to_h { |path| [path, Digest::SHA256.file(path).hexdigest] },
    topic_slug_source: Topic.instance_method(:slug).source_location,
    pg_exec_source: PG::Connection.instance_method(:exec).source_location,
    miniprofiler_version: Gem.loaded_specs.fetch("rack-mini-profiler").version.to_s,
    default_scope_sources: Topic.default_scopes.map { |scope| scope.scope.source_location }})

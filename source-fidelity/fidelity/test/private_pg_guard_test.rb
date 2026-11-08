# frozen_string_literal: true
require "minitest/autorun"
require "json"
require "digest"
require_relative "../tools/private_pg_oracle_guard"
module FidelityOracleIsolation
  class UnsafeEndpoint < SecurityError; end
end
class PrivatePGGuardTest < Minitest::Test
  def classify(sql, callers: [], phase: "rails_running")
    FidelityPrivatePG.classify!(sql, callers: callers, phase: phase)
  end
  def test_only_original_css_and_wizard_writes
    css = ["app/models/stylesheet_cache.rb"]
    wizard = ["lib/wizard.rb", "lib/site_settings/db_provider.rb"]
    assert_equal({operation: "INSERT", table: "stylesheet_cache"}, classify("INSERT INTO \"stylesheet_cache\" (content) VALUES ('a; DELETE FROM users; \'\'quoted\'\'') RETURNING id", callers: css))
    assert_equal "DELETE", classify("DELETE FROM public.stylesheet_cache WHERE id < 5", callers: css)[:operation]
    assert_equal "site_settings", classify("INSERT INTO site_settings (name,value) VALUES ('bypass_wizard_check','t')", callers: wizard)[:table]
    ["INSERT INTO users (id) VALUES (1)", "UPDATE stylesheet_cache SET content='x'", "DELETE FROM site_settings", "CREATE TABLE things (id int)", "TRUNCATE stylesheet_cache"].each do |sql|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { classify(sql, callers: css + wizard) }
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { classify("INSERT INTO stylesheet_cache VALUES (1)") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { classify("INSERT INTO site_settings(name) VALUES ('other')", callers: wizard) }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { classify("INSERT INTO site_settings(name) VALUES ('bypass_wizard_check')", callers: wizard, phase: "preflight") }
  end
  def test_quotes_comments_multistatement_and_external_effects_fail_closed
    assert_nil classify("/* SELECT */ SELECT 'DELETE; CREATE', $$UPDATE;$$ AS text;")
    assert_nil classify("BEGIN")
    assert_nil classify("SET SESSION timezone TO 'UTC'")
    ["SELECT 1; DELETE FROM users", "WITH x AS (DELETE FROM users RETURNING *) SELECT * FROM x", "SELECT pg_notify('x','y')", "SELECT pg_read_file('/etc/passwd')", "SELECT dblink('host=elsewhere','SELECT 1')", "SELECT nextval('x')", "SET ROLE postgres", "SET default_transaction_read_only=off", "COPY users TO PROGRAM 'x'", "DO $$BEGIN END$$", "SELECT 'unterminated", "/* unterminated"].each do |sql|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint, sql) { classify(sql) }
    end
  end
  def test_connection_host_port_database_user_and_backend_parent
    original_manifest = FidelityPrivatePG.method(:manifest!)
    original_process = FidelityPrivatePG.method(:process)
    manifest = {"socket_directory" => "/owned/socket", "port" => 54321, "database" => "discourse_development", "user" => "discourse", "postgres_pid" => 123}
    connection = Struct.new(:host, :port, :db, :user, :backend_pid).new("/owned/socket", 54321, "discourse_development", "discourse", 456)
    FidelityPrivatePG.define_singleton_method(:manifest!) { manifest }
    FidelityPrivatePG.define_singleton_method(:process) { |_| {parent: 123} }
    assert_equal manifest, FidelityPrivatePG.connection!(connection)
    [[:host, "127.0.0.1"], [:port, 5499], [:db, "postgres"], [:user, "fixture_owner"]].each do |field, wrong|
      changed = connection.dup; changed[field] = wrong
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { FidelityPrivatePG.connection!(changed) }
    end
    FidelityPrivatePG.define_singleton_method(:process) { |_| {parent: 999} }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { FidelityPrivatePG.connection!(connection) }
  ensure
    FidelityPrivatePG.define_singleton_method(:manifest!, original_manifest)
    FidelityPrivatePG.define_singleton_method(:process, original_process)
  end
end

class PrivatePGConstructorPolicyTest < Minitest::Test
  def test_normalization_refuses_shared_unknown_role_and_option_overrides_before_connection
    require "pg"
    original = FidelityPrivatePG.method(:manifest!)
    m = {"socket_directory" => "/owned/socket", "port" => 54321, "database" => "discourse_development", "user" => "discourse"}
    FidelityPrivatePG.define_singleton_method(:manifest!) { m }
    policy = Object.new.extend(FidelityPrivatePG::Policy)
    params = {host: "/owned/socket", port: 54321, dbname: "discourse_development", user: "discourse"}
    before = ENV["PGOPTIONS"]
    ENV["PGOPTIONS"] = "-c statement_timeout=15000"
    assert_equal "/owned/socket", policy.normalize_pg_args([], params)[1]["host"]
    [{host: "127.0.0.1", port: 5499}, {port: 6399}, {user: "fixture_owner"}, {dbname: "postgres"},
     {service: "other"}, {hostaddr: "127.0.0.1"}, {options: "-c default_transaction_read_only=off"}].each do |wrong|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { policy.normalize_pg_args([], params.merge(wrong)) }
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { policy.normalize_pg_args([params, "extra"], {}) }
  ensure
    ENV["PGOPTIONS"] = before
    FidelityPrivatePG.define_singleton_method(:manifest!, original)
  end
end

class PrivatePGLargeSQLTest < Minitest::Test
  def test_megabyte_unicode_css_is_preserved_without_quadratic_character_indexing
    require "timeout"
    css = "a→b{content:'x';}/* SELECT; DELETE; */" * 40000
    map = JSON.generate({sourcesContent: [css]})
    sql = "INSERT INTO stylesheet_cache(content,source_map) VALUES ('#{css.gsub("'", "''")}','#{map.gsub("'", "''")}') RETURNING id"
    tokens = Timeout.timeout(3) { FidelityPrivatePG.tokens(sql) }
    assert_equal [css, map], tokens.select { |kind, _| kind == :literal }.map(&:last)
    effect = Timeout.timeout(3) do
      FidelityPrivatePG.classify!(sql, callers: ["app/models/stylesheet_cache.rb"], phase: "rails_running")
    end
    assert_equal({operation: "INSERT", table: "stylesheet_cache"}, effect)
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      FidelityPrivatePG.classify!(sql + "; DELETE FROM users", callers: ["app/models/stylesheet_cache.rb"], phase: "rails_running")
    end
  end
end

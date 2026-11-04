# frozen_string_literal: true
require "minitest/autorun"
require "tmpdir"
require "json"
require "fileutils"

# Small API-compatible doubles keep these negative controls before Rails boot
# and prove rejection happens before a network-capable connection is created.
module RedisClient
  class Config
    attr_reader :path, :host, :port
    def initialize(path: nil, host: nil, port: nil, **)
      @path, @host, @port = path, host, port
    end
  end
  module ConnectionMixin
    def connect; :connected; end
    def call(command, *); [:dispatched, command]; end
    def call_pipelined(commands, *); [:pipelined, commands]; end
  end
  class RubyConnection
    include ConnectionMixin
    def initialize(config); @config = config; end
    private
    def connect; :network_started; end
  end
  class HiredisConnection < RubyConnection; end
end

module PG
  class Connection
    class << self
      def connect(**params); new(**params); end
      def connect_start(**params); new(**params); end
      def async_connect(**params); new(**params); end
      def sync_connect(**params); new(**params); end
      def open(**params); connection = new(**params); yield connection if block_given?; connection; end
      def setdb(host, port, options, _tty, dbname); new(host: host, port: port, options: options, dbname: dbname); end
      def setdblogin(host, port, options, _tty, dbname, user, password)
        new(host: host, port: port, options: options, dbname: dbname, user: user, password: password)
      end
    end
    attr_reader :params
    def initialize(**params); @params = params; end
    def exec(sql)
      raise "readonly override reached connection" if sql.match?(/default_transaction_read_only\s*=\s*off/i)
      [{ "current_database" => "discourse_development", "inet_server_addr" => "127.0.0.1",
         "inet_server_port" => "5499", "current_setting" => "on" }]
    end
    def exec_params(sql, *); exec(sql); end
    def async_exec(sql, *); exec(sql); end
    def send_query(sql, *); exec(sql); end
    def send_query_params(sql, *); exec(sql); end
    def prepare(name, sql, *); @prepared ||= {}; @prepared[name] = sql; end
    def send_prepare(name, sql, *); prepare(name, sql); end
    def exec_prepared(name, *); exec((@prepared || {}).fetch(name)); end
    def send_query_prepared(name, *); exec_prepared(name); end
    def close; end
  end
end

require_relative "../tools/oracle_isolation"

class OracleIsolationTest < Minitest::Test
  def test_alias_based_profiler_wraps_guard_without_recursion_or_hook_omission
    PG::Connection.class_eval do
      alias_method :fidelity_without_profiler, :exec
      attr_reader :fidelity_profile_calls
      define_method(:exec) do |*args, &block|
        @fidelity_profile_calls = (@fidelity_profile_calls || 0) + 1
        fidelity_without_profiler(*args, &block)
      end
    end
    connection = PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development")
    before = connection.fidelity_profile_calls
    connection.exec("SELECT 1")
    assert_equal before + 1, connection.fidelity_profile_calls
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("UPDATE topics SET visible = false") }
  ensure
    PG::Connection.class_eval do
      alias_method :exec, :fidelity_without_profiler
      remove_method :fidelity_without_profiler
    end
  end

  def test_unknown_unix_socket_is_rejected_even_outside_redis
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      FidelityOracleIsolation.assert_socket_address!(Socket.sockaddr_un("/tmp/fidelity-unowned.sock"))
    end
  end

  def test_wrong_pg_conninfo_is_not_silently_replaced_by_environment_defaults
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.connect("host=127.0.0.2 port=5499 dbname=discourse_development")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.connect("host=127.0.0.1 port=5499 dbname=not_the_task_database")
    end
  end

  def test_concurrent_effect_evidence_is_complete_jsonl
    path = File.join(@dir, "concurrent.jsonl")
    threads = 4.times.map do |actor|
      Thread.new do
        12.times { |i| FidelityOracleIsolation.append_json!(path, { actor: actor, index: i, text: "x" * 20_000 }) }
      end
    end
    threads.each(&:value)
    records = File.readlines(path).map { |line| JSON.parse(line) }
    assert_equal 48, records.length
    assert_equal 48, records.map { |record| [record["actor"], record["index"]] }.uniq.length
    assert records.all? { |record| record["text"].length == 20_000 }
  end

  def test_rescued_policy_denials_remain_auditable
    path = File.join(@dir, "rejected.jsonl")
    ENV["FIDELITY_REJECTION_LOG"] = path
    ENV["FIDELITY_ORACLE_PHASE"] = "oracle"
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      FidelityOracleIsolation.assert_pg_sql_readonly!("DELETE FROM topics")
    end
    event = JSON.parse(File.read(path))
    assert_equal "oracle", event["phase"]
    assert_includes event["message"], "write SQL rejected"
  ensure
    ENV.delete("FIDELITY_REJECTION_LOG")
    ENV.delete("FIDELITY_ORACLE_PHASE")
  end

  def setup
    @dir = Dir.mktmpdir("oracle-isolation-")
    @host = "127.0.0.1"
    @port = 16379
    @evidence = File.join(@dir, "owner.json")
    File.write(@evidence, JSON.generate(status: "ready", pid: Process.pid, info_process_id: Process.pid,
                                        host: @host, port: @port,
                                        config: { bind: [@host], port: @port, loopback_only: true }))
    ENV["FIDELITY_VALKEY_HOST"] = @host
    ENV["FIDELITY_VALKEY_PORT"] = @port.to_s
    ENV["FIDELITY_VALKEY_PID"] = Process.pid.to_s
    ENV["FIDELITY_VALKEY_EVIDENCE"] = @evidence
    ENV["FIDELITY_VALKEY_WRITE_LOG"] = File.join(@dir, "writes.jsonl")
    ENV["FIDELITY_PG_CONNECTION_LOG"] = File.join(@dir, "pg-connections.jsonl")
    FidelityOracleIsolation.install_redis!
    FidelityOracleIsolation.install_pg!
  end

  def teardown
    %w[FIDELITY_VALKEY_HOST FIDELITY_VALKEY_PORT FIDELITY_VALKEY_PID FIDELITY_VALKEY_EVIDENCE FIDELITY_VALKEY_WRITE_LOG FIDELITY_PG_CONNECTION_LOG].each { |k| ENV.delete(k) }
    FileUtils.remove_entry(@dir) if @dir && File.exist?(@dir)
  end

  def test_redis_shared_and_other_tcp_endpoints_rejected_before_connection
    [["127.0.0.1", 6399], ["127.0.0.1", @port + 1], ["127.0.0.1", 5499], ["8.8.8.8", @port]].each do |host, port|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
        RedisClient::Config.new(host: host, port: port)
      end
      cfg = RedisClient::Config.allocate
      cfg.instance_variable_set(:@path, nil)
      cfg.instance_variable_set(:@host, host)
      cfg.instance_variable_set(:@port, port)
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { FidelityOracleIsolation.assert_redis_config!(cfg) }
      connection = Object.new
      connection.instance_variable_set(:@config, cfg)
      connection.extend(RedisClient::ConnectionMixin)
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.connect }
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.call(["SET", "k", "v"], 1) }
      [RedisClient::RubyConnection, RedisClient::HiredisConnection].each do |driver|
        low_level = driver.new(cfg)
        assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { low_level.send(:connect) }
      end
    end
  end

  def test_unknown_unix_socket_rejected
    cfg = RedisClient::Config.allocate
    cfg.instance_variable_set(:@path, "/tmp/unowned.sock")
    cfg.instance_variable_set(:@host, nil)
    cfg.instance_variable_set(:@port, nil)
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { FidelityOracleIsolation.assert_redis_config!(cfg) }
  end

  def test_owned_tcp_redis_config_and_pipeline_are_allowed_and_recorded
    cfg = RedisClient::Config.new(host: @host, port: @port)
    assert FidelityOracleIsolation.assert_redis_config!(cfg)
    connection = Object.new
    connection.instance_variable_set(:@config, cfg)
    connection.extend(RedisClient::ConnectionMixin)
    assert_equal :connected, connection.connect
    assert_equal [:pipelined, [["SET", "actual-effect", "kept"]]],
                 connection.call_pipelined([["SET", "actual-effect", "kept"]], [])
    write = JSON.parse(File.readlines(ENV.fetch("FIDELITY_VALKEY_WRITE_LOG")).last)
    assert_equal "set", write.fetch("command")
    assert_equal "actual-effect", write.fetch("key")
    assert_equal "successful_reply", write.fetch("stage")
    assert_equal "Symbol", write.fetch("response_class")
    assert_equal 64, write.fetch("arguments_sha256").length
  end

  def test_network_socket_guard_allows_only_pg_and_owned_fixture
    assert FidelityOracleIsolation.assert_socket_target!("127.0.0.1", 5499)
    assert FidelityOracleIsolation.assert_socket_target!(@host, @port)
    [["127.0.0.1", 6399], ["127.0.0.1", @port + 1], ["8.8.8.8", 5499], ["localhost", 5499]].each do |host, port|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
        FidelityOracleIsolation.assert_socket_target!(host, port)
      end
    end
  end

  def test_pg_wrong_host_database_port_and_readonly_override_rejected_pre_connect
    [{ host: "10.0.0.1", port: "5499", dbname: "discourse_development" },
     { host: "127.0.0.1", port: "5499", dbname: "postgres" },
     { host: "127.0.0.1", port: "6399", dbname: "discourse_development" }].each do |params|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { PG::Connection.connect(**params) }
      %i[connect_start async_connect sync_connect new].each do |constructor|
        assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { PG::Connection.public_send(constructor, **params) }
      end
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development",
                             options: "-c default_transaction_read_only=off")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development", service: "external")
    end
    old_service, old_hostaddr = ENV["PGSERVICE"], ENV["PGHOSTADDR"]
    ENV["PGSERVICE"] = "external"
    ENV["PGHOSTADDR"] = "127.0.0.2"
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development")
    end
    ENV["PGSERVICE"] = old_service
    ENV["PGHOSTADDR"] = old_hostaddr
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.connect("postgres://discourse@127.0.0.1:5499/discourse_development?options=-c%20default_transaction_read_only%3Doff")
    end
    [{ host: "127.0.0.1", port: "5499", dbname: "discourse_development", hostaddr: "10.0.0.1" },
     { host: "127.0.0.1", port: "5499", dbname: "discourse_development", service: "external" }].each do |params|
      assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { PG::Connection.connect(**params) }
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.open(host: "127.0.0.1", port: "5432", dbname: "discourse_development")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.setdb("127.0.0.1", "6399", "", nil, "discourse_development")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.setdblogin("127.0.0.1", "5499", "", nil, "postgres", "discourse", "secret")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      PG::Connection.new("host=127.0.0.1 port=5499 dbname=discourse_development", "unvalidated-extra")
    end
  end

  def test_pg_supported_constructors_force_readonly_and_sql_override_is_rejected
    connection = PG::Connection.async_connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development")
    assert_includes connection.params.fetch("options"), "default_transaction_read_only=on"
    assert_equal "on", connection.exec("SELECT current_setting('default_transaction_read_only')").first["current_setting"]
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      connection.exec("SET default_transaction_read_only=off")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("UPDATE topics SET visible = false") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("WITH changed AS (DELETE FROM topics RETURNING *) SELECT * FROM changed") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("BEGIN TRANSACTION READ WRITE") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) do
      connection.exec("SELECT set_config('default_transaction_read_only', 'off', false)")
    end
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("SET LOCAL transaction_read_only TO 'off'") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("RESET default_transaction_read_only") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec("SET SESSION AUTHORIZATION postgres") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.prepare("bad", "UPDATE topics SET visible=false") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.send_prepare("bad", "SELECT set_config('x', 'y', false)") }
    assert_raises(FidelityOracleIsolation::UnsafeEndpoint) { connection.exec_prepared("unknown") }
    connection.prepare("read_only", "SELECT 1")
    assert_equal "on", connection.exec_prepared("read_only").first["current_setting"]
  end

  def test_pg_connection_evidence_is_written_only_after_verified_open
    connection = PG::Connection.connect(host: "127.0.0.1", port: "5499", dbname: "discourse_development")
    self.assert_instance_of PG::Connection, connection
    rows = File.readlines(ENV.fetch("FIDELITY_PG_CONNECTION_LOG")).map { |line| JSON.parse(line) }
    proof = rows.last
    assert_equal "discourse_development", proof.fetch("database")
    assert_equal "127.0.0.1", proof.fetch("address")
    assert_equal 5499, proof.fetch("port")
    assert_equal "on", proof.fetch("default_transaction_read_only")
    assert proof.fetch("constructor")
  end
end

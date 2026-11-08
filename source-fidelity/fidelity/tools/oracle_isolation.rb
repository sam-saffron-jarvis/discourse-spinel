# frozen_string_literal: true
# Test-only guards. Load after redis/pg gems, but BEFORE config/environment.rb.
# Isolation is verified from live client config and a private child evidence file;
# merely setting environment variables is not sufficient.
require "json"
require "uri"
require "digest"
require "time"
require "socket"
require "rbconfig"
require "pg" unless defined?(PG::Connection)
require "redis" unless defined?(RedisClient::ConnectionMixin)

module FidelityOracleIsolation
  class UnsafeEndpoint < SecurityError
    def initialize(message)
      super(message)
      path = ENV["FIDELITY_REJECTION_LOG"]
      if path
        FidelityOracleIsolation.append_json!(path, { phase: ENV["FIDELITY_ORACLE_PHASE"],
          message: message, caller: caller(1, 16) })
      end
    end
  end

  def self.append_json!(path, record)
    File.open(path, "a") do |file|
      # Original logging/cache effects can run on multiple Rails threads.
      # Keep whole JSONL records serialized, not separate puts/newline writes.
      file.flock(File::LOCK_EX)
      file.write(JSON.generate(record) + "\n")
      file.flush
    end
  end

  def self.fixture
    host = ENV.fetch("FIDELITY_VALKEY_HOST") { raise UnsafeEndpoint, "missing private Valkey host" }
    port = Integer(ENV.fetch("FIDELITY_VALKEY_PORT") { raise UnsafeEndpoint, "missing private Valkey port" })
    pid = Integer(ENV.fetch("FIDELITY_VALKEY_PID") { raise UnsafeEndpoint, "missing sandbox PID" })
    evidence_path = ENV.fetch("FIDELITY_VALKEY_EVIDENCE") { raise UnsafeEndpoint, "missing sandbox ownership evidence" }
    evidence = JSON.parse(File.read(evidence_path))
    unless host == "127.0.0.1" && ![5499, 6399].include?(port) && evidence["status"] == "ready" &&
           evidence["pid"] == pid && evidence["info_process_id"] == pid && evidence["host"] == host &&
           evidence["port"] == port && evidence.dig("config", "bind") == [host] &&
           evidence.dig("config", "port") == port && evidence.dig("config", "loopback_only") == true &&
           Process.kill(0, pid)
      raise UnsafeEndpoint, "Valkey ownership evidence does not attest this private loopback endpoint"
    end
    [host, port, pid]
  rescue Errno::ENOENT, Errno::ESRCH, JSON::ParserError, ArgumentError => error
    raise UnsafeEndpoint, "invalid Valkey ownership evidence: #{error.message}"
  end

  def self.assert_socket_target!(host, port)
    normalized_port = Integer(port)
    fixture_host, fixture_port, = fixture
    return true if host.to_s == "127.0.0.1" && normalized_port == 5499
    return true if host.to_s == fixture_host && normalized_port == fixture_port
    raise UnsafeEndpoint, "oracle TCP socket rejected: #{host.inspect}:#{port.inspect}; only task PostgreSQL and owned Valkey are allowed"
  rescue ArgumentError, TypeError
    raise UnsafeEndpoint, "oracle TCP socket rejected: #{host.inspect}:#{port.inspect}"
  end

  def self.assert_socket_address!(sockaddr)
    address = sockaddr.is_a?(Addrinfo) ? sockaddr : Addrinfo.new(sockaddr)
    return assert_owned_readonly_vips!(address.unix_path) if address.unix?
    port, host = Socket.unpack_sockaddr_in(sockaddr)
    assert_socket_target!(host, port)
  rescue ArgumentError, SocketError => error
    raise UnsafeEndpoint, "unrecognized TCP socket destination rejected: #{error.message}"
  end

  # Unchanged development Rails boot checks libvips' version through its own
  # short-lived private worker. This is not an external/shared service or a
  # writable oracle fixture: allow only that pinned read-only version call,
  # after proving the socket belongs to this process's original worker child.
  # Redis's independent config/dispatch guards still reject EVERY Unix path.
  def self.original_vips_sources!
    reference = File.realpath(File.expand_path("../../discourse", __dir__))
    root = File.realpath(ENV.fetch("FIDELITY_VIPS_ORIGINAL_APPLICATION_ROOT", reference))
    unless root == reference
      build = File.realpath(File.expand_path("../build", __dir__))
      unless root.start_with?(build + File::SEPARATOR)
        raise UnsafeEndpoint, "vips source root is not the original checkout or an owned build archive"
      end
    end
    expected = JSON.parse(ENV.fetch("FIDELITY_VIPS_ORIGINAL_SOURCE_HASHES"))
    paths = %w[lib/discourse_vips.rb lib/discourse_vips/worker_process.rb script/discourse_vips_worker]
    raise UnsafeEndpoint, "missing original vips source attestation" unless expected.is_a?(Hash) && expected.keys.sort == paths.sort
    paths.each do |relative|
      unless Digest::SHA256.file(File.join(reference, relative)).hexdigest == expected.fetch(relative) &&
             Digest::SHA256.file(File.join(root, relative)).hexdigest == expected.fetch(relative)
        raise UnsafeEndpoint, "original vips source changed"
      end
    end
    root
  rescue KeyError, JSON::ParserError, Errno::ENOENT
    raise UnsafeEndpoint, "missing or invalid original vips source attestation"
  end

  def self.vips_process_identity!(worker)
    pid = worker.pid
    raise UnsafeEndpoint, "invalid original vips child PID" unless pid.is_a?(Integer) && pid.positive?
    status = File.read("/proc/#{pid}/status")
    start = File.read("/proc/#{pid}/stat").rpartition(") ").last.split.fetch(19)
    executable = File.realpath("/proc/#{pid}/exe")
    socket = File.lstat(worker.socket_path)
    directory = File.lstat(File.dirname(worker.socket_path))
    unless status.match?(/^PPid:\s+#{Process.pid}$/) && executable == File.realpath(RbConfig.ruby) &&
           socket.socket? && socket.uid == Process.euid && directory.directory? && directory.uid == Process.euid &&
           directory.mode & 0o777 == 0o700 && [socket.dev, socket.ino] == worker.instance_variable_get(:@socket_identity)
      raise UnsafeEndpoint, "vips worker ownership could not be proven"
    end
    unless start == File.read("/proc/#{pid}/stat").rpartition(") ").last.split.fetch(19)
      raise UnsafeEndpoint, "original vips child changed during ownership proof"
    end
    { pid: pid, start: start, executable: executable, socket: worker.socket_path, socket_identity: [socket.dev, socket.ino] }
  rescue Errno::ENOENT, Errno::ESRCH, IndexError
    raise UnsafeEndpoint, "private vips worker disappeared before ownership proof"
  end

  def self.attest_original_vips_start!(worker, source)
    root = original_vips_sources!
    expected = File.join(root, "lib/discourse_vips/worker_process.rb")
    unless source == expected && defined?(DiscourseVips::WorkerProcess) && worker.instance_of?(DiscourseVips::WorkerProcess) &&
           %i[start worker_command worker_environment pid socket_path shutdown discard remove_socket].all? { |name| worker.method(name).source_location&.first == expected } &&
           Process.method(:spawn).source_location.nil?
      raise UnsafeEndpoint, "vips start did not use the pinned original worker and core spawn"
    end
    identity = vips_process_identity!(worker)
    @vips_starts ||= {}
    @vips_starts[worker.object_id] = [worker, identity]
    log_vips(stage: "original_start_attested", **identity)
  end

  def self.install_vips_start_observer!
    return if @vips_start_observer
    # Observation only: no original method is wrapped/replaced or invoked twice.
    # start's ensure has run and the original Process.spawn has returned its PID.
    @vips_start_observer = TracePoint.new(:return) do |event|
      next unless event.method_id == :start && event.defined_class&.name == "DiscourseVips::WorkerProcess"
      attest_original_vips_start!(event.self, event.path)
    end
    @vips_start_observer.enable
  end

  def self.attested_vips_identity!(worker)
    original_vips_sources!
    observed, original = (@vips_starts || {})[worker.object_id]
    raise UnsafeEndpoint, "unobserved original vips worker start" unless observed.equal?(worker) && original
    current = vips_process_identity!(worker)
    raise UnsafeEndpoint, "original vips child identity changed" unless current == original
    current
  end

  def self.assert_owned_readonly_vips!(path)
    unless defined?(DiscourseVips::Client) && defined?(DiscourseVips::WorkerProcess)
      raise UnsafeEndpoint, "unowned Unix socket rejected"
    end
    worker = DiscourseVips::Client.instance_variable_get(:@worker_process)
    root = original_vips_sources!
    expected_call = "#{root}/lib/discourse_vips.rb:14:"
    unless worker.is_a?(DiscourseVips::WorkerProcess) && worker.socket_path == path && caller.any? { |frame| frame.start_with?(expected_call) }
      raise UnsafeEndpoint, "Unix socket is not the original private vips version worker"
    end
    identity = attested_vips_identity!(worker)
    pid = identity.fetch(:pid)
    command = File.binread("/proc/#{pid}/cmdline").split("\0")
    unless command.include?("#{root}/script/discourse_vips_worker") || command == ["discourse vips worker"]
      raise UnsafeEndpoint, "original vips child command changed"
    end
    @vips_workers ||= {}
    unless @vips_workers.key?(pid)
      @vips_workers[pid] = worker
      log_vips(stage: "owned_readonly_version", pid: pid, parent_pid: Process.pid, socket: path)
    end
    true
  rescue Errno::ENOENT
    raise UnsafeEndpoint, "private vips worker disappeared before ownership proof"
  end

  def self.log_vips(record)
    path = ENV["FIDELITY_VIPS_LOG"]
    append_json!(path, record) if path
  end

  def self.cleanup_vips!
    # An attested original start is owned even if a later startup failure
    # prevented the version connection. Never adopt an unobserved process.
    workers = (@vips_starts || {}).values.to_h { |worker, identity| [identity.fetch(:pid), worker] }
    workers.merge!(@vips_workers || {})
    workers.each do |pid, worker|
      original_vips_sources!
      zombie = false
      unless worker.instance_variable_get(:@closed)
        observed, original = (@vips_starts || {}).fetch(worker.object_id)
        raise UnsafeEndpoint, "unobserved vips cleanup target" unless observed.equal?(worker) && original.fetch(:pid) == pid
        fields = File.read("/proc/#{pid}/stat").rpartition(") ").last.split
        zombie = fields[0] == "Z" && fields[1] == Process.pid.to_s && fields[19] == original.fetch(:start)
      end
      if zombie
        # This same attested child is already dead and cannot reuse its PID
        # until reaped. Reap it, close only its own pipe/socket, never signal
        # a process group after the PID has become available for reuse.
        Process.waitpid(pid)
        worker.discard
        worker.send(:remove_socket)
      else
        attested_vips_identity!(worker) unless worker.instance_variable_get(:@closed)
        worker.shutdown
      end
      begin
        Process.kill(0, pid)
        raise UnsafeEndpoint, "owned vips child did not exit"
      rescue Errno::ESRCH
        log_vips(stage: "owned_child_exited", pid: pid)
      end
    end
    @vips_workers = {}
    @vips_starts = {}
  end

  def self.extract_endpoint(config)
    values = {}
    %i[path socket unixsocket host port url].each do |name|
      values[name] = config.public_send(name) if config.respond_to?(name)
    rescue StandardError
      # Some client config accessors deliberately raise when another transport is selected.
    end
    config.instance_variables.each do |ivar|
      key = ivar.to_s.delete_prefix("@").to_sym
      values[key] ||= config.instance_variable_get(ivar) if %i[path socket unixsocket host port url].include?(key)
    end
    options = config.instance_variable_get(:@options)
    values.merge!(options) if options.is_a?(Hash)
    values
  end

  def self.assert_redis_config!(config)
    host, port, = fixture
    endpoint = extract_endpoint(config)
    uri = endpoint[:url] || endpoint["url"]
    if uri
      parsed = URI.parse(uri.to_s)
      unless parsed.scheme == "redis" && parsed.host == host && parsed.port == port
        raise UnsafeEndpoint, "Redis URL must name owned loopback Valkey #{host}:#{port}, got #{uri.inspect}"
      end
    end
    path = endpoint[:path] || endpoint["path"] || endpoint[:socket] || endpoint["socket"] ||
           endpoint[:unixsocket] || endpoint["unixsocket"]
    configured_host = endpoint[:host] || endpoint["host"]
    configured_port = endpoint[:port] || endpoint["port"]
    unless path.nil? && configured_host.to_s == host && configured_port.to_s == port.to_s
      raise UnsafeEndpoint, "Redis client must use only owned loopback Valkey #{host}:#{port}; config=#{endpoint.inspect}"
    end
    true
  end

  READ_ONLY_COMMANDS = %w[ping hello auth select quit info get mget exists exists? ttl pttl type keys scan hget hmget hgetall hkeys hvals hlen hexists lrange llen lindex scard sismember smembers srandmember sscan zrange zrevrange zrangebyscore zrevrangebyscore zscore zcard zcount zrank zrevrank zscan time dbsize].freeze

  def self.check_command!(command)
    command = command.first if command.is_a?(Array) && command.length == 1 && command.first.is_a?(Array)
    values = command.is_a?(Array) ? command : [command]
    raise UnsafeEndpoint, "empty Redis command rejected" if values.first.to_s.empty?
    true
  end

  # Redis values are bytes (the real profiler stores Marshal payloads), not
  # necessarily UTF-8 JSON strings. Encode only the TEST evidence copy; never
  # modify the command or reply sent to/returned from the owned fixture.
  def self.evidence_value(value)
    case value
    when String
      if value.valid_encoding? && (value.encoding == Encoding::UTF_8 || value.ascii_only?)
        value
      else
        { binary_hex: value.unpack1("H*"), encoding: value.encoding.name }
      end
    when Array
      value.map { |item| evidence_value(item) }
    when Hash
      value.to_a.map { |key, item| [evidence_value(key), evidence_value(item)] }
    else
      value
    end
  end

  def self.record_command!(command, response)
    values = command.is_a?(Array) ? command : [command]
    name = values.first.to_s.downcase
    return if READ_ONLY_COMMANDS.include?(name) || (name == "client" && %w[setname setinfo getname id info].include?(values[1].to_s.downcase))
    log = ENV["FIDELITY_VALKEY_WRITE_LOG"]
    return unless log
    successful = !(defined?(RedisClient::Error) && response.is_a?(RedisClient::Error))
    record = { stage: successful ? "successful_reply" : "error_reply", command: name, key: evidence_value(values[1]),
               arguments_sha256: Digest::SHA256.hexdigest(JSON.generate(evidence_value(values.drop(1)))),
               response_class: response.class.name, response_sha256: Digest::SHA256.hexdigest(JSON.generate(evidence_value(response))),
               timestamp: Time.now.utc.iso8601(6), caller: caller(2, 100) }
    append_json!(log, record)
  end

  def self.install_socket!
    return if @socket_installed
    socket_class_guard = Module.new do
      def tcp(host, port, *args, **kwargs, &block)
        FidelityOracleIsolation.assert_socket_target!(host, port)
        super
      end

      def connect(sockaddr, *args, **kwargs, &block)
        FidelityOracleIsolation.assert_socket_address!(sockaddr)
        super
      end
    end
    Socket.singleton_class.prepend(socket_class_guard)

    tcp_guard = Module.new do
      def new(host, port, *args, **kwargs, &block)
        FidelityOracleIsolation.assert_socket_target!(host, port)
        super
      end
    end
    TCPSocket.singleton_class.prepend(tcp_guard)

    socket_instance_guard = Module.new do
      def connect(sockaddr, *args, **kwargs, &block)
        FidelityOracleIsolation.assert_socket_address!(sockaddr)
        super
      end

      def connect_nonblock(sockaddr, *args, **kwargs, &block)
        FidelityOracleIsolation.assert_socket_address!(sockaddr)
        super
      end
    end
    Socket.prepend(socket_instance_guard)
    @socket_installed = true
  end

  def self.prepend_driver_guards!(klass)
    guard = Module.new
    if klass.instance_method(:connect).owner == klass
      guard.define_method(:connect) do |*args, **kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(instance_variable_get(:@config) || instance_variable_get(:@client)&.config)
        super(*args, **kwargs, &block)
      end
    end
    if klass.instance_method(:call).owner == klass
      guard.define_method(:call) do |command, *args, **kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(instance_variable_get(:@config) || instance_variable_get(:@client)&.config)
        FidelityOracleIsolation.check_command!(command)
        response = super(command, *args, **kwargs, &block)
        FidelityOracleIsolation.record_command!(command, response)
        response
      end
    end
    if klass.instance_method(:call_pipelined).owner == klass
      guard.define_method(:call_pipelined) do |commands, *args, **kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(instance_variable_get(:@config) || instance_variable_get(:@client)&.config)
        commands.each { |command| FidelityOracleIsolation.check_command!(command) }
        responses = super(commands, *args, **kwargs, &block)
        commands.each_with_index { |command, index| FidelityOracleIsolation.record_command!(command, responses[index]) }
        responses
      end
    end
    klass.prepend(guard) unless guard.instance_methods(false).empty?
  end

  def self.install_redis!
    return if @redis_installed
    raise "redis-client is unavailable" unless defined?(RedisClient::ConnectionMixin)
    guard = Module.new do
      define_method(:initialize) do |*args, **kwargs, &block|
        super(*args, **kwargs, &block).tap do
          FidelityOracleIsolation.assert_redis_config!(self)
        end
      end

      define_method(:new_client) do |**kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(self)
        super(**kwargs, &block)
      end

      define_method(:new_pool) do |**kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(self)
        super(**kwargs, &block)
      end
    end
    RedisClient::Config.prepend(guard) if defined?(RedisClient::Config)

    guard_connection = Module.new do
      define_method(:connect) do |*args, **kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(instance_variable_get(:@config) || instance_variable_get(:@client)&.config)
        super(*args, **kwargs, &block)
      end
      define_method(:call) do |command, *args, **kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(instance_variable_get(:@config) || instance_variable_get(:@client)&.config)
        FidelityOracleIsolation.check_command!(command)
        response = super(command, *args, **kwargs, &block)
        FidelityOracleIsolation.record_command!(command, response)
        response
      end
      define_method(:call_pipelined) do |commands, *args, **kwargs, &block|
        FidelityOracleIsolation.assert_redis_config!(instance_variable_get(:@config) || instance_variable_get(:@client)&.config)
        commands.each { |command| FidelityOracleIsolation.check_command!(command) }
        responses = super(commands, *args, **kwargs, &block)
        commands.each_with_index { |command, index| FidelityOracleIsolation.record_command!(command, responses[index]) }
        responses
      end
    end
    RedisClient::ConnectionMixin.prepend(guard_connection)
    if defined?(RedisClient::RubyConnection)
      prepend_driver_guards!(RedisClient::RubyConnection)
    end
    if defined?(RedisClient::HiredisConnection)
      prepend_driver_guards!(RedisClient::HiredisConnection)
    end
    @redis_installed = true
  end

  PG_TARGET = { "host" => "127.0.0.1", "port" => "5499", "dbname" => "discourse_development" }.freeze
  READ_ONLY_OPTIONS = "-c default_transaction_read_only=on -c statement_timeout=15000"
  UNSAFE_READONLY_OPTION = /(?:default_transaction_read_only|transaction_read_only)\s*=\s*(?:off|false|0)|\btransaction\s+read\s+write/i

  def self.normalize_pg_args(args, kwargs)
    positional = args.dup
    params = if positional.first.is_a?(Hash)
      positional.shift.transform_keys(&:to_s)
    elsif positional.first.is_a?(String)
      string = positional.shift
      raise UnsafeEndpoint, "PostgreSQL conninfo attempts to disable read-only" if string.match?(UNSAFE_READONLY_OPTION)
      begin
        if string.match?(/\Apostgres(?:ql)?:\/\//)
          uri = URI.parse(string)
          query = URI.decode_www_form(uri.query.to_s).to_h
          { "host" => uri.host, "port" => uri.port&.to_s, "dbname" => uri.path.delete_prefix("/"),
            "user" => uri.user, "password" => uri.password }.merge(query)
        elsif defined?(PG::Connection) && PG::Connection.respond_to?(:conninfo_parse)
          PG::Connection.conninfo_parse(string).to_h { |field| [field[:keyword].to_s, field[:val]] }
        else
          string.scan(/([A-Za-z_]+)\s*=\s*(?:'((?:\\.|[^'])*)'|([^\s]+))/).to_h do |key, quoted, bare|
            [key, quoted || bare]
          end
        end
      rescue URI::InvalidURIError => error
        raise UnsafeEndpoint, "invalid PostgreSQL connection string: #{error.message}"
      end
    else
      {}
    end
    raise UnsafeEndpoint, "unsupported positional PostgreSQL constructor arguments" unless positional.empty?
    params.merge!(kwargs.transform_keys(&:to_s))
    %w[PGHOST PGPORT PGDATABASE].each_with_index do |key, index|
      env_key = %w[host port dbname][index]
      params[env_key] ||= ENV[key]
    end
    PG_TARGET.each do |key, expected|
      actual = params[key]
      raise UnsafeEndpoint, "PostgreSQL #{key}=#{actual.inspect} is outside task target" unless actual.to_s == expected
    end
    params["hostaddr"] ||= ENV["PGHOSTADDR"]
    params["service"] ||= ENV["PGSERVICE"]
    if params["service"].to_s != ""
      raise UnsafeEndpoint, "PostgreSQL service overrides are not allowed"
    end
    params.delete("hostaddr") if params["hostaddr"].to_s.empty?
    params.delete("service") if params["service"].to_s.empty?
    if params["hostaddr"] && params["hostaddr"].to_s != "127.0.0.1"
      raise UnsafeEndpoint, "PostgreSQL hostaddr override #{params['hostaddr'].inspect} is outside task target"
    end
    requested_options = params["options"].to_s
    raise UnsafeEndpoint, "PostgreSQL startup options attempt to disable read-only" if requested_options.match?(UNSAFE_READONLY_OPTION)
    params["options"] = [requested_options, READ_ONLY_OPTIONS].reject(&:empty?).join(" ")
    [positional, params]
  end

  def self.verify_pg_connection!(connection, constructor: "unknown")
    db = connection.exec("SELECT current_database(), inet_server_addr(), inet_server_port(), current_setting('default_transaction_read_only')").first
    unless db["current_database"] == "discourse_development" && db["inet_server_addr"] == "127.0.0.1" &&
           db["inet_server_port"].to_s == "5499" && db["current_setting"] == "on"
      connection.close rescue nil
      raise UnsafeEndpoint, "opened PostgreSQL connection failed task/read-only verification: #{db.inspect}"
    end
    log = ENV["FIDELITY_PG_CONNECTION_LOG"]
    if log
      proof = { constructor: constructor, pid: Process.pid, database: db["current_database"],
                address: db["inet_server_addr"], port: db["inet_server_port"].to_i,
                default_transaction_read_only: db["current_setting"], verified_at: Time.now.utc.iso8601(6) }
      append_json!(log, proof)
    end
    connection
  end

  def self.assert_pg_sql_readonly!(sql)
    statement = sql.to_s.sub(/\A(?:\s|\/\*.*?\*\/|--[^\n]*\n)*/m, "")
    write_statement = statement.match?(/\A(?:INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE|GRANT|REVOKE|COMMENT|REFRESH|REINDEX|CLUSTER|VACUUM|ANALYZE|CALL|DO|COPY\s+.+\s+FROM)\b/i) ||
      statement.match?(/\AWITH\b.*\b(?:INSERT|UPDATE|DELETE|MERGE)\b/im)
    raise UnsafeEndpoint, "PostgreSQL write SQL rejected" if write_statement
    normalized = statement.downcase.gsub(/[\"']/, "")
    readonly_off = normalized.match?(/\bset\s+(?:(?:session|local)\s+)?(?:default_transaction_read_only|transaction_read_only)\b[^;]*\b(?:off|false|0)\b/) ||
      normalized.match?(/\b(?:begin|start|set\s+transaction)\b[^;]*\bread\s+write\b/)
    if normalized.match?(/\bset_config\s*\(/) || normalized.match?(/\breset\b/) ||
       normalized.match?(/\b(?:set\s+session\s+authorization|set\s+(?:local\s+)?role)\b/) || readonly_off
      raise UnsafeEndpoint, "PostgreSQL session/read-only override rejected"
    end
    true
  end

  def self.install_pg!
    return if @pg_installed
    raise "pg gem is unavailable" unless defined?(PG::Connection)
    env_options = ENV["PGOPTIONS"].to_s
    raise UnsafeEndpoint, "PGOPTIONS attempts to disable read-only" if env_options.match?(UNSAFE_READONLY_OPTION)
    ENV["PGOPTIONS"] = [env_options, READ_ONLY_OPTIONS].reject(&:empty?).join(" ")

    wrapper = Module.new
    constructor_names = %i[connect connect_start async_connect sync_connect new open]
    constructor_names.each do |method|
      next unless PG::Connection.respond_to?(method)
      defer_verification = %i[connect_start async_connect].include?(method)
      wrapper.define_method(method) do |*args, **kwargs, &block|
        positional, params = FidelityOracleIsolation.normalize_pg_args(args, kwargs)
        wrapped_block = if block
          proc do |connection|
            FidelityOracleIsolation.verify_pg_connection!(connection, constructor: method)
            block.call(connection)
          end
        end
        result = super(*positional, **params, &(wrapped_block || block))
        if result.is_a?(PG::Connection) && !defer_verification
          FidelityOracleIsolation.verify_pg_connection!(result, constructor: method)
        else
          result
        end
      end
    end

    %i[setdb setdblogin].each do |method|
      next unless PG::Connection.respond_to?(method)
      wrapper.define_method(method) do |*args, **kwargs, &block|
        raise FidelityOracleIsolation::UnsafeEndpoint, "unexpected #{method} keyword arguments" unless kwargs.empty?
        width = method == :setdb ? 5 : 7
        values = args + Array.new([width - args.length, 0].max)
        host, port, options, tty, dbname, user, password = values
        raise FidelityOracleIsolation::UnsafeEndpoint, "PostgreSQL tty option is not supported" if tty
        _, safe = FidelityOracleIsolation.normalize_pg_args([], { host: host, port: port, options: options, dbname: dbname })
        safe_args = [safe["host"], safe["port"], safe["options"], nil, safe["dbname"]]
        safe_args.concat([user, password]) if method == :setdblogin
        result = super(*safe_args, &block)
        result.is_a?(PG::Connection) ? FidelityOracleIsolation.verify_pg_connection!(result, constructor: method) : result
      end
    end
    PG::Connection.singleton_class.prepend(wrapper)

    async_guard = Module.new do
      define_method(:connect_poll) do |*args, **kwargs, &block|
        result = super(*args, **kwargs, &block)
        if defined?(PG::PGRES_POLLING_OK) && result == PG::PGRES_POLLING_OK
          FidelityOracleIsolation.verify_pg_connection!(self, constructor: "connect_poll")
        end
        result
      end
    end
    PG::Connection.prepend(async_guard) if PG::Connection.method_defined?(:connect_poll)

    # Install direct wrappers over the current methods, not a prepend layer.
    # Alias-based instrumentation loaded later (e.g. MiniProfiler) must capture
    # this checked method and then call it, rather than aliasing a prepend whose
    # `super` re-enters the new instrumentation and recurses indefinitely.
    # The profiler's original outer body still runs; no hook is disabled.
    %i[exec exec_params async_exec async_exec_params sync_exec sync_exec_params
       send_query send_query_params query].each do |method|
      next unless PG::Connection.method_defined?(method)
      original = PG::Connection.instance_method(method)
      PG::Connection.define_method(method) do |sql, *args, **kwargs, &block|
        FidelityOracleIsolation.assert_pg_sql_readonly!(sql)
        original.bind_call(self, sql, *args, **kwargs, &block)
      end
    end
    %i[prepare send_prepare sync_prepare async_prepare].each do |method|
      next unless PG::Connection.method_defined?(method)
      original = PG::Connection.instance_method(method)
      PG::Connection.define_method(method) do |name, sql, *args, **kwargs, &block|
        FidelityOracleIsolation.assert_pg_sql_readonly!(sql)
        result = original.bind_call(self, name, sql, *args, **kwargs, &block)
        (@fidelity_prepared_sql ||= {})[name.to_s] = sql.to_s
        result
      end
    end
    %i[exec_prepared send_query_prepared sync_exec_prepared async_exec_prepared].each do |method|
      next unless PG::Connection.method_defined?(method)
      original = PG::Connection.instance_method(method)
      PG::Connection.define_method(method) do |name, *args, **kwargs, &block|
        sql = (@fidelity_prepared_sql || {})[name.to_s]
        raise FidelityOracleIsolation::UnsafeEndpoint, "unverified PostgreSQL prepared statement #{name.inspect}" unless sql
        FidelityOracleIsolation.assert_pg_sql_readonly!(sql)
        original.bind_call(self, name, *args, **kwargs, &block)
      end
    end
    @pg_installed = true
  end

  def self.install!
    install_vips_start_observer!
    install_socket!
    install_redis!
    install_pg!
  end
end

if !ENV["FIDELITY_PRIVATE_PG_MANIFEST"].to_s.empty?
  require_relative "private_pg_oracle_guard"
  FidelityPrivatePG.activate!
end
FidelityOracleIsolation.install! if defined?(RedisClient::ConnectionMixin) && defined?(PG::Connection)

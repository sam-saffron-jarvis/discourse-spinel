# frozen_string_literal: true
# One-use ORIGINAL Rails HTML fixture only. Never enabled by normal JSON/native
# runners. The shared readonly PG policy remains unchanged when no manifest exists.
require "json"
require "digest"
require "uri"
require "strscan"

module FidelityPrivatePG
  ROOT = File.expand_path("../..", __dir__)
  AUTHORIZATION = File.join(ROOT, "run/PRIVATE_PG_HTML_AUTHORIZATION_20261107.json")
  USAGE = File.join(ROOT, "run/PRIVATE_PG_HTML_USAGE_20261107.json")

  def self.refuse(message)
    raise FidelityOracleIsolation::UnsafeEndpoint, message
  end

  def self.process(pid)
    fields = File.read("/proc/#{Integer(pid)}/stat").rpartition(")").last.split
    refuse("private PG process is dead") if fields[0] == "Z"
    {ticks: fields.fetch(19), parent: fields.fetch(1).to_i}
  end

  def self.usage_record
    File.open(USAGE) do |file|
      file.flock(File::LOCK_SH)
      JSON.parse(file.read)
    end
  end

  def self.manifest!
    path = File.realpath(ENV.fetch("FIDELITY_PRIVATE_PG_MANIFEST"))
    build = File.realpath(File.join(ROOT, "fidelity/build"))
    refuse("private PG manifest outside owned build") unless path.start_with?(build + "/")
    stat = File.stat(path)
    refuse("private PG manifest ownership/mode") unless stat.uid == Process.euid && stat.mode & 0o077 == 0
    m = JSON.parse(File.read(path))
    refuse("private PG manifest kind") unless m["schema"] == 1 && m["kind"] == "owned_original_html_pg_20261107"
    refuse("private PG authorization path") unless m["authorization_path"] == AUTHORIZATION
    auth = JSON.parse(File.read(AUTHORIZATION))
    refuse("private PG approval mismatch") unless auth["experiment_limit"] == 1 &&
      auth["allowed_actor"] == "original Rails HTML reference only" &&
      auth["user_action"] == "ask_user selection: Allow one disposable experiment" &&
      Digest::SHA256.file(AUTHORIZATION).hexdigest == m["authorization_sha256"]
    usage = usage_record
    refuse("private PG usage is not live and exclusively claimed") unless usage["status"] == "claimed" &&
      usage["authorization_sha256"] == m["authorization_sha256"] && usage["runner_pid"] == m["runner_pid"] &&
      usage["runner_start_ticks"] == m["runner_start_ticks"] && usage["output"] == m["output"]
    if usage["phase"] == "rails_running"
      refuse("private PG repeated Rails invocation") unless usage["rails_invocations"] == 1 && usage["rails_pid"] == Process.pid
    elsif usage["phase"] == "preflight"
      refuse("private PG preflight after Rails invocation") unless usage["rails_invocations"] == 0
    else
      refuse("private PG not in an authorized active phase")
    end
    runner = process(m.fetch("runner_pid"))
    refuse("private PG runner identity") unless runner[:ticks] == m["runner_start_ticks"] && Process.ppid == m["runner_pid"]
    refuse("private PG prohibited port") if [5499, 6399].include?(Integer(m.fetch("port")))
    refuse("private PG role/database") unless m["database"] == "discourse_development" && m["user"] == "discourse"
    data = File.realpath(m.fetch("data_directory"))
    refuse("private PG datadir placement") unless data == File.join(File.dirname(path), "pg-data")
    [data, File.realpath(m.fetch("socket_directory"))].each do |directory|
      s = File.stat(directory)
      refuse("private PG directory ownership/mode") unless s.directory? && s.uid == Process.euid && s.mode & 0o077 == 0
    end
    server = Integer(m.fetch("postgres_pid"))
    server_identity = process(server)
    refuse("private PG server identity") unless server_identity[:ticks] == m["postgres_start_ticks"] && server_identity[:parent] == m["runner_pid"]
    executable = File.realpath("/proc/#{server}/exe")
    refuse("private PG executable") unless executable == m["postgres_executable"] && File.basename(executable) == "postgres"
    refuse("private PG command/datadir") unless File.binread("/proc/#{server}/cmdline").split("\0").include?(data)
    refuse("private PG pidfile") unless File.readlines(File.join(data, "postmaster.pid")).first.to_i == server
    socket = File.stat(File.join(m["socket_directory"], ".s.PGSQL.#{m['port']}"))
    refuse("private PG socket identity") unless socket.socket? && socket.uid == Process.euid &&
      [socket.dev, socket.ino] == m["socket_identity"]
    m
  rescue KeyError, JSON::ParserError, ArgumentError, Errno::ENOENT, IndexError => error
    refuse("unproved private PG fixture: #{error.class}")
  end

  def self.connection!(connection)
    m = manifest!
    refuse("PG connection not owned private endpoint") unless connection.host == m["socket_directory"] &&
      connection.port.to_i == m["port"] && connection.db == m["database"] && connection.user == m["user"]
    refuse("private PG backend not child of owned server") unless process(connection.backend_pid)[:parent] == m["postgres_pid"]
    m
  end

  # Tokenize SQL without treating quoted CSS/source-map contents as SQL. This is
  # a deliberately small fail-closed lexer, not a replacement SQL implementation.
  def self.tokens(sql)
    scanner = StringScanner.new(sql.to_s)
    out = []
    until scanner.eos?
      if scanner.skip(/\s+/) || scanner.skip(/--[^\n]*(?:\n|\z)/)
        next
      elsif scanner.scan(/\/\*/)
        depth = 1
        while depth > 0
          chunk = scanner.scan_until(/\/\*|\*\//)
          refuse("unterminated PG comment") unless chunk
          depth += chunk.end_with?("/*") ? 1 : -1
        end
      elsif scanner.peek(1) == "'"
        quoted = scanner.scan(/'(?:[^']+|'')*'/m)
        refuse("unterminated PG quoted token") unless quoted
        out << [:literal, quoted[1...-1].gsub("''", "'")]
      elsif scanner.peek(1) == '"'
        quoted = scanner.scan(/"(?:[^"]+|"")*"/m)
        refuse("unterminated PG quoted token") unless quoted
        out << [:word, quoted[1...-1].gsub('""', '"')]
      elsif (delimiter = scanner.scan(/\$(?:[a-zA-Z_]\w*)?\$/))
        body = scanner.scan_until(Regexp.new(Regexp.escape(delimiter)))
        refuse("unterminated PG dollar quote") unless body
        out << [:literal, body[0...-delimiter.length]]
      elsif (word = scanner.scan(/[a-zA-Z_][a-zA-Z_0-9$]*/))
        out << [:word, word]
      else
        out << [:punct, scanner.getch]
      end
    end
    out
  end

  def self.classify!(sql, callers: [], phase: "preflight")
    ts = tokens(sql)
    ts.pop if ts.last == [:punct, ";"]
    refuse("multiple PG statements") if ts.include?([:punct, ";"])
    words = ts.select { |kind, _| kind == :word }.map { |_, value| value.downcase }
    verb = words.first
    refuse("empty PG SQL") unless verb
    forbidden = /\A(?:dblink\w*|lo_import|lo_export|pg_read_\w*|pg_write_\w*|pg_ls_\w*|pg_notify|pg_reload_conf|pg_terminate_backend|pg_cancel_backend|set_config|setval|nextval)\z/
    refuse("private PG external/admin function") if words.any? { |word| word.match?(forbidden) }
    if %w[select show begin commit rollback savepoint release].include?(verb)
      refuse("PG nested mutation") if words.any? { |word| %w[insert update delete merge create alter drop truncate copy call do].include?(word) }
      return nil
    end
    if verb == "with" || verb == "explain"
      refuse("PG writable CTE/explain") if words.any? { |word| %w[insert update delete merge create alter drop truncate copy call do analyze].include?(word) }
      return nil
    end
    if verb == "set"
      variable = (words - %w[set session local]).first
      allowed = %w[client_encoding client_min_messages standard_conforming_strings timezone search_path intervalstyle application_name statement_timeout lock_timeout idle_in_transaction_session_timeout]
      refuse("private PG session override") unless allowed.include?(variable)
      return nil
    end
    refuse("PG write outside original HTML phase") unless phase == "rails_running"
    target = if verb == "insert" && words[1] == "into"
      words[2] == "public" ? words[3] : words[2]
    elsif verb == "delete" && words[1] == "from"
      words[2] == "public" ? words[3] : words[2]
    elsif verb == "update"
      words[1] == "public" ? words[2] : words[1]
    end
    if target == "stylesheet_cache" && %w[insert delete].include?(verb)
      refuse("stylesheet write not original cache callback") unless callers.include?("app/models/stylesheet_cache.rb")
    elsif target == "site_settings" && %w[insert update].include?(verb)
      refuse("setting write not original wizard/provider path") unless callers.include?("lib/wizard.rb") && callers.include?("lib/site_settings/db_provider.rb")
      refuse("setting write is not bypass_wizard_check") unless ts.include?([:literal, "bypass_wizard_check"])
    else
      refuse("private PG write outside approved CSS/wizard scope")
    end
    {operation: verb.upcase, table: target}
  end

  def self.statement!(connection, sql)
    m = connection!(connection)
    usage = usage_record
    if usage["phase"] == "rails_running"
      refuse("private PG HTML actor identity") unless usage["rails_pid"] == Process.pid
    end
    root = File.realpath(ENV.fetch("FIDELITY_VIPS_ORIGINAL_APPLICATION_ROOT")) + "/"
    callers = caller_locations.map(&:absolute_path).compact.select { |path| path.start_with?(root) }.map { |path| path.delete_prefix(root) }.uniq
    effect = classify!(sql, callers: callers, phase: usage["phase"])
    [m, effect, callers]
  end

  module Policy
    def normalize_pg_args(args, kwargs)
      positional = args.dup
      params = if positional.first.is_a?(Hash)
        positional.shift.transform_keys(&:to_s)
      elsif positional.first.is_a?(String)
        PG::Connection.conninfo_parse(positional.shift).to_h { |field| [field[:keyword].to_s, field[:val]] }
      else
        {}
      end
      FidelityPrivatePG.refuse("private PG positional arguments") unless positional.empty?
      params.merge!(kwargs.transform_keys(&:to_s))
      %w[host port dbname user].zip(%w[PGHOST PGPORT PGDATABASE PGUSER]).each { |key, env| params[key] ||= ENV[env] }
      m = FidelityPrivatePG.manifest!
      {"host" => m["socket_directory"], "port" => m["port"].to_s, "dbname" => m["database"], "user" => m["user"]}.each do |key, expected|
        FidelityPrivatePG.refuse("private PG target #{key} mismatch") unless params[key].to_s == expected
      end
      %w[hostaddr service servicefile password passfile].each do |key|
        FidelityPrivatePG.refuse("private PG endpoint/credential override") unless params[key].to_s.empty?
        params.delete(key)
      end
      [params["options"], ENV["PGOPTIONS"]].compact.each do |options|
        FidelityPrivatePG.refuse("private PG startup options") unless options.match?(/\A(?:\s*(?:-c\s*)?(?:statement_timeout|lock_timeout)=\d+\s*)*\z/)
      end
      [[], params.compact]
    end

    def verify_pg_connection!(connection, constructor: "unknown")
      m = FidelityPrivatePG.connection!(connection)
      row = connection.exec("SELECT current_database(),current_user,current_setting('data_directory') AS data_directory,current_setting('port') AS port,current_setting('listen_addresses') AS listen_addresses,current_setting('default_transaction_read_only') AS default_transaction_read_only").first
      unless row["current_database"] == m["database"] && row["current_user"] == m["user"] && row["data_directory"] == m["data_directory"] &&
          row["port"].to_i == m["port"] && row["listen_addresses"] == "" && row["default_transaction_read_only"] == "off"
        connection.close
        FidelityPrivatePG.refuse("private PG live backend/datadir verification")
      end
      append_json!(ENV.fetch("FIDELITY_PG_CONNECTION_LOG"), {constructor: constructor, backend_pid: connection.backend_pid,
        postmaster_pid: m["postgres_pid"], port: m["port"], owned_datadir_verified: true, user: m["user"], database: m["database"], private_only: true})
      connection
    end

    def assert_socket_target!(host, port)
      fixture_host, fixture_port, = fixture
      return true if host.to_s == fixture_host && Integer(port) == fixture_port
      FidelityPrivatePG.refuse("private HTML rejects shared/unknown TCP target")
    end

    def assert_socket_address!(sockaddr)
      address = sockaddr.is_a?(Addrinfo) ? sockaddr : Addrinfo.new(sockaddr)
      m = FidelityPrivatePG.manifest!
      if address.unix? && address.unix_path == File.join(m["socket_directory"], ".s.PGSQL.#{m['port']}")
        return true
      end
      super
    end

    def check_command!(command)
      values = command.is_a?(Array) ? command.flatten(1) : [command]
      if values.drop(1).any? { |value| value.to_s.match?(/(?:\A|:)(?:queue|queues|schedule|retry|dead)(?::|\z)/) }
        FidelityPrivatePG.refuse("private HTML may not enqueue jobs")
      end
      super
    end

    def install_pg!
      return if @pg_installed
      constructors = Module.new
      %i[connect connect_start async_connect sync_connect new open].each do |method|
        next unless PG::Connection.respond_to?(method)
        constructors.define_method(method) do |*args, **kwargs, &block|
          positional, params = FidelityOracleIsolation.normalize_pg_args(args, kwargs)
          safe_block = block && proc { |connection| FidelityOracleIsolation.verify_pg_connection!(connection, constructor: method); block.call(connection) }
          result = super(*positional, **params, &(safe_block || block))
          if result.is_a?(PG::Connection) && !%i[connect_start async_connect].include?(method)
            FidelityOracleIsolation.verify_pg_connection!(result, constructor: method)
          end
          result
        end
      end
      %i[setdb setdblogin].each do |method|
        constructors.define_method(method) { |*| FidelityPrivatePG.refuse("legacy private PG constructor unsupported") }
      end
      PG::Connection.singleton_class.prepend(constructors)
      polling = Module.new do
        def connect_poll(*args)
          result = super
          FidelityOracleIsolation.verify_pg_connection!(self, constructor: "connect_poll") if result == PG::PGRES_POLLING_OK
          result
        end
      end
      PG::Connection.prepend(polling)
      %i[exec exec_params async_exec async_exec_params sync_exec sync_exec_params send_query send_query_params query prepare send_prepare sync_prepare async_prepare exec_prepared send_query_prepared sync_exec_prepared async_exec_prepared].each do |method|
        next unless PG::Connection.method_defined?(method)
        original = PG::Connection.instance_method(method)
        preparing = %i[prepare send_prepare sync_prepare async_prepare].include?(method)
        prepared = %i[exec_prepared send_query_prepared sync_exec_prepared async_exec_prepared].include?(method)
        PG::Connection.define_method(method) do |first, *args, **kwargs, &block|
          sql = if prepared
            (@fidelity_private_sql || {}).fetch(first.to_s) { FidelityPrivatePG.refuse("unverified private PG prepared SQL") }
          elsif preparing
            args.first
          else
            first
          end
          m, effect, callers = FidelityPrivatePG.statement!(self, sql)
          result = original.bind_call(self, first, *args, **kwargs, &block)
          (@fidelity_private_sql ||= {})[first.to_s] = sql.to_s if preparing
          if effect && !preparing
            FidelityOracleIsolation.append_json!(ENV.fetch("FIDELITY_PRIVATE_PG_WRITE_LOG"), effect.merge(
              sql_sha256: Digest::SHA256.hexdigest(sql.to_s), backend_pid: backend_pid, postmaster_pid: m["postgres_pid"],
              original_callers: callers, successful: true))
          end
          result
        end
      end
      @pg_installed = true
    end
  end

  def self.activate!
    manifest!
    FidelityOracleIsolation.singleton_class.prepend(Policy)
  end
end

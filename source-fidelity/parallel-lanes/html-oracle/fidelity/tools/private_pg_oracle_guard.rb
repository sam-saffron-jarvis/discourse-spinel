# frozen_string_literal: true
# Explicit opt-in for ONE authorized private PostgreSQL HTML oracle instance.
# Absent the manifest, the original shared-PG read-only guard remains unchanged.
require "json"
require "digest"
require "uri"

module FidelityPrivatePG
  AUTHORIZATION = "/home/agent/work/discourse-spinel/run/PRIVATE_PG_HTML_ORACLE_AUTHORIZATION.json"

  def self.enabled?
    !ENV["FIDELITY_PRIVATE_PG_MANIFEST"].to_s.empty?
  end

  def self.refuse(message)
    raise FidelityOracleIsolation::UnsafeEndpoint, message
  end

  def self.ticks(pid)
    File.read("/proc/#{Integer(pid)}/stat").rpartition(")").last.split.fetch(19)
  end

  def self.manifest!
    path = File.realpath(ENV.fetch("FIDELITY_PRIVATE_PG_MANIFEST"))
    stat = File.stat(path)
    refuse("private PG manifest must be owned and private") unless stat.uid == Process.euid && stat.mode & 0o077 == 0
    m = JSON.parse(File.read(path))
    refuse("wrong private PG manifest type") unless m["kind"] == "owned_disposable_html_oracle_pg" && m["schema"] == 1
    auth = File.realpath(m.fetch("authorization_path"))
    refuse("unrecognized private PG authorization") unless auth == File.realpath(AUTHORIZATION)
    refuse("changed private PG authorization") unless Digest::SHA256.file(auth).hexdigest == m["authorization_sha256"]
    a = JSON.parse(File.read(auth))
    refuse("private writable PG was not authorized") unless a["selected_option"] == "Allow writable disposable copy" && a["one_experiment_not_blanket_permission"]
    refuse("shared PG port may never be a private fixture") if Integer(m.fetch("port")) == 5499
    refuse("wrong private PG database") unless m["database"] == "discourse_development" && m["user"] == "discourse"
    data = File.realpath(m.fetch("data_directory"))
    refuse("data directory is outside owned fixture") unless data == File.join(File.dirname(path), "pg-data")
    data_stat = File.stat(data)
    refuse("private PG data ownership/mode failure") unless data_stat.uid == Process.euid && data_stat.directory? && data_stat.mode & 0o077 == 0
    server = Integer(m.fetch("postgres_pid"))
    runner = Integer(m.fetch("runner_pid"))
    refuse("private PG process identity changed") unless ticks(server) == m["postgres_start_ticks"] && ticks(runner) == m["runner_start_ticks"]
    refuse("private PG executable changed") unless File.readlink("/proc/#{server}/exe") == m["postgres_executable"] && File.basename(m["postgres_executable"]) == "postgres"
    command = File.binread("/proc/#{server}/cmdline").split("\0")
    refuse("private PG command/data mismatch") unless command.include?(data)
    refuse("private PG pidfile mismatch") unless File.readlines(File.join(data, "postmaster.pid")).first.to_i == server
    socket_dir = File.realpath(m.fetch("socket_directory"))
    s = File.stat(socket_dir)
    refuse("private PG socket directory ownership failure") unless s.directory? && s.uid == Process.euid && s.mode & 0o077 == 0
    socket = File.stat(File.join(socket_dir, ".s.PGSQL.#{m.fetch('port')}"))
    refuse("private PG socket ownership failure") unless socket.socket? && socket.uid == Process.euid
    m
  rescue KeyError, JSON::ParserError, ArgumentError, Errno::ENOENT => e
    refuse("unproved private PostgreSQL fixture: #{e.class}")
  end

  def self.target!
    m = manifest!
    { "host" => m["socket_directory"], "port" => m["port"].to_s, "dbname" => m["database"] }
  end

  def self.connection!(connection)
    m = manifest!
    refuse("connection is not the private PG endpoint") unless connection.host == m["socket_directory"] &&
      connection.port.to_i == m["port"].to_i && connection.db == m["database"] && connection.user == m["user"]
    pid = connection.backend_pid
    ppid = File.read("/proc/#{pid}/status")[/^PPid:\s+(\d+)/, 1].to_i
    refuse("PG backend does not belong to owned postmaster") unless ppid == m["postgres_pid"].to_i
    m
  rescue Errno::ENOENT
    refuse("private PG backend disappeared")
  end

  def self.statement!(connection, sql)
    connection!(connection)
    text = sql.to_s.sub(/\A(?:\s|\/\*.*?\*\/|--[^\n]*\n)*/m, "")
    # The authorized application can mutate only this private database. Server
    # administration, OS programs/files and remote database connections are not
    # implied by that approval, even for a privileged private test role.
    if text.match?(/\A(?:ALTER\s+SYSTEM|(?:CREATE|ALTER|DROP)\s+(?:TABLESPACE|FOREIGN|SERVER|ROLE|USER)|COPY\b.*\bPROGRAM\b)/im) ||
       text.match?(/\b(?:dblink(?:_connect)?|lo_export|lo_import|pg_read_file|pg_write_file|pg_reload_conf)\s*\(/i)
      refuse("private PG external/server administration statement rejected")
    end
    true
  end

  def self.record_statement(connection, sql)
    return unless ENV["FIDELITY_PRIVATE_PG_WRITE_LOG"]
    text = sql.to_s.lstrip
    operation = text[/\A(?:INSERT|UPDATE|DELETE|MERGE|CREATE|ALTER|DROP|TRUNCATE)\b/i]
    return unless operation
    FidelityOracleIsolation.append_json!(ENV["FIDELITY_PRIVATE_PG_WRITE_LOG"], {
      **FidelityOracleObservation.context, operation: operation.upcase,
      sql_sha256: Digest::SHA256.hexdigest(sql.to_s), private_port: connection.port,
      backend_pid: connection.backend_pid, stage: "successful_private_statement",
      original_app_callers: caller.select { |frame| frame.include?(ENV["FIDELITY_DISCOURSE_ROOT"].to_s) }.first(12)
    })
  end
end

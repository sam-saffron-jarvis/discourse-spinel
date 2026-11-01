# frozen_string_literal: true
# Spinel native adaptation of rack-mini-profiler 5.0.0 TimerStruct/Page/Request/Sql.
# No Rack, Rails, monkey-patches, subprocesses, global or thread-local request state.
require "json"
require "securerandom"

class SpinelMiniProfiler
  VERSION = "5.0.0"
  ASSET_VERSION = "0ab236f63a9cce6719807f4cd6470f29"
  MAX_RESULTS = 32
  MAX_BYTES = 1048576
  TTL_SECONDS = 300

  def self.clock
    Process.clock_gettime(Process::CLOCK_MONOTONIC)
  end

  def self.escape(text)
    text.gsub("&", "&amp;").gsub("<", "&lt;").gsub(">", "&gt;").gsub('"', "&quot;").gsub("'", "&#39;")
  end

  # Retain SQL structure and $n placeholders, NEVER bind values, comments or
  # literal contents. Quoted identifiers are conservative redactions too. Scan
  # nested comments, doubled quotes, E/backslash and tagged dollar strings rather
  # than using a regex that might expose the rest of a secret after an escape.
  def self.redact(sql)
    return "[SQL omitted: exceeds 16384 bytes]" if sql.bytesize > 16384
    output = ""
    i = 0
    while i < sql.length
      char = sql[i, 1]
      pair = sql[i, 2]
      if pair == "--"
        i += 2
        i += 1 while i < sql.length && sql[i, 1] != "\n"
        output += " "
      elsif pair == "/*"
        depth = 1
        i += 2
        while i < sql.length && depth > 0
          if sql[i, 2] == "/*"
            depth += 1
            i += 2
          elsif sql[i, 2] == "*/"
            depth -= 1
            i += 2
          else
            i += 1
          end
        end
        output += " "
      elsif char == "'" || char == '"'
        quote = char
        i += 1
        while i < sql.length
          if sql[i, 1] == "\\"
            i += 2
          elsif sql[i, 1] == quote
            i += 1
            if sql[i, 1] == quote
              i += 1
            else
              break
            end
          else
            i += 1
          end
        end
        output += quote + "?" + quote
      elsif char == "$" && (tag = sql[i..-1].to_s.match(/\A\$(?:[A-Za-z_][A-Za-z0-9_]*)?\$/))
        delimiter = tag[0].to_s
        i += delimiter.length
        ending = sql[i..-1].to_s.index(delimiter)
        i = ending ? i + ending + delimiter.length : sql.length
        output += "'?'"
      elsif char == "$" && sql[i + 1, 1].to_s.match?(/[0-9]/)
        start = i
        i += 1
        i += 1 while i < sql.length && sql[i, 1].match?(/[0-9]/)
        output += sql[start, i - start]
      elsif char.match?(/[0-9]/) && (i == 0 || !sql[i - 1, 1].match?(/[A-Za-z0-9_]/))
        i += 1
        i += 1 while i < sql.length && sql[i, 1].match?(/[A-Za-z0-9_.]/)
        output += "?"
      else
        output += char
        i += 1
      end
    end
    output.bytesize > 4096 ? "[SQL omitted: redacted text exceeds 4096 bytes]" : output
  end

  def initialize(max_results = MAX_RESULTS, max_bytes = MAX_BYTES, ttl_seconds = TTL_SECONDS)
    raise "invalid profiler storage limits" unless max_results > 0 && max_results <= MAX_RESULTS && max_bytes > 0 && max_bytes <= MAX_BYTES && ttl_seconds >= 0 && ttl_seconds <= TTL_SECONDS
    @max_results = max_results
    @max_bytes = max_bytes
    @ttl_seconds = ttl_seconds
    @ids = []
    @json = {}
    @saved_at = {}
    @bytes = 0
  end

  def start(path, method)
    # Names reach upstream doT templates as HTML. Never include query strings,
    # incoming Host, cookies, auth, headers, client timings or request bodies.
    raise "invalid profiler request name" unless path.match?(/\A\/[A-Za-z0-9_\/.\-]*\z/) && ["GET", "POST"].include?(method)
    SpinelMiniProfilerRequest.new(path, method)
  end

  def prune
    now = SpinelMiniProfiler.clock
    while !@ids.empty? && (now - @saved_at[@ids[0]].to_f >= @ttl_seconds || @ids.length > @max_results || @bytes > @max_bytes)
      id = @ids.shift.to_s
      @bytes -= @json[id].to_s.bytesize
      @json.delete(id)
      @saved_at.delete(id)
    end
  end

  def save(request)
    id = request.id
    return id if @json.key?(id)
    json = request.finish
    @ids << id
    @json[id] = json
    @saved_at[id] = SpinelMiniProfiler.clock
    @bytes += json.bytesize
    prune
    id
  end

  def result(id)
    prune
    @json[id]
  end

  def bootstrap(base_path, id, template)
    raise "invalid profiler base path" unless base_path.empty? || base_path.match?(/\A(?:\/[A-Za-z0-9_-]+)+\z/)
    path = base_path + "/mini-profiler-resources/"
    values = {
      "path" => path, "url" => path + "includes.js?v=" + ASSET_VERSION,
      "cssUrl" => path + "includes.css?v=" + ASSET_VERSION,
      "version" => ASSET_VERSION, "ids" => id, "currentId" => id,
      "verticalPosition" => "top", "horizontalPosition" => "left",
      "showTrivial" => "true", "showChildren" => "true", "maxTracesToShow" => "10",
      "showControls" => "false", "showTotalSqlCount" => "true", "authorized" => "true",
      "toggleShortcut" => "alt+p", "startHidden" => "false", "collapseResults" => "false",
      "htmlContainer" => "body", "hiddenCustomFields" => "", "cspNonce" => "",
      "hotwireTurboDriveSupport" => "false"
    }
    script = template
    values.each { |key, value| script = script.gsub("{" + key + "}", SpinelMiniProfiler.escape(value)) }
    script
  end
end

class SpinelMiniProfilerRequest
  MAX_SQL = 128
  attr_reader :id

  def initialize(path, method)
    @id = SecureRandom.hex(16)
    @path = path
    @method = method
    @started = SpinelMiniProfiler.clock
    @started_at = (Time.now.to_f * 1000).to_i
    @sql = []
    @sql_count = 0
    @sql_ms = 0.0
    @failed_count = 0
    @finished = false
    @result_json = ""
  end

  def record(sql, started, failed)
    return if @finished
    elapsed = (SpinelMiniProfiler.clock - started) * 1000
    @sql_count += 1
    @sql_ms += elapsed
    @failed_count += 1 if failed
    return if @sql.length >= MAX_SQL
    @sql << {
      "execute_type" => 3, "formatted_command_string" => SpinelMiniProfiler.escape(SpinelMiniProfiler.redact(sql)),
      "stack_trace_snippet" => failed ? "Native PG call failed; error text and call-site stacks are not collected." : "Native PG exec/exec_params; call-site stacks are not collected.",
      "start_milliseconds" => (started - @started) * 1000, "duration_milliseconds" => elapsed,
      "first_fetch_duration_milliseconds" => elapsed, "parameters" => nil, "row_count" => 0,
      "class_name" => nil, "parent_timing_id" => @id + "-root", "cached" => false,
      "is_duplicate" => false, "failed" => failed
    }
  end

  def finish
    return @result_json unless @result_json.empty?
    @finished = true
    elapsed = (SpinelMiniProfiler.clock - @started) * 1000
    has_sql = @sql_count > 0
    root = {
      "id" => @id + "-root", "name" => @method + " " + @path,
      "duration_milliseconds" => elapsed, "duration_without_children_milliseconds" => elapsed,
      "start_milliseconds" => 0, "parent_timing_id" => nil, "children" => [], "has_children" => false,
      "key_values" => nil, "has_sql_timings" => has_sql, "has_duplicate_sql_timings" => false,
      "trivial_duration_threshold_milliseconds" => 2, "sql_timings" => @sql,
      "sql_timings_duration_milliseconds" => @sql_ms, "is_trivial" => false, "is_root" => true,
      "depth" => 0, "executed_readers" => 0, "executed_scalars" => 0, "executed_non_queries" => 0,
      "custom_timing_stats" => {}, "custom_timings" => {}
    }
    @result_json = JSON.generate({
      "id" => @id, "name" => @path, "started" => (@started * 1000).to_i, "started_at" => @started_at,
      "started_formatted" => "/Date(" + @started_at.to_s + ")/", "machine_name" => "native",
      "level" => 0, "user" => "private dev", "has_user_viewed" => true, "client_timings" => nil,
      "duration_milliseconds" => elapsed, "has_trivial_timings" => true, "has_all_trivial_timings" => false,
      "trivial_duration_threshold_milliseconds" => 2, "head" => nil, "sql_count" => @sql_count,
      "cached_sql_count" => 0, "duration_milliseconds_in_sql" => @sql_ms, "has_sql_timings" => has_sql,
      "has_duplicate_sql_timings" => false, "executed_readers" => 0, "executed_scalars" => 0,
      "executed_non_queries" => 0, "custom_timing_names" => [], "custom_timing_stats" => {},
      "custom_fields" => { "Runtime" => "Spinel native; request work excluding socket transfer",
        "SQL details" => "Literals/comments/binds redacted; no stacks, reader counts or duplicate detection",
        "Omitted SQL details" => (@sql_count - @sql.length).to_s, "Failed PG calls" => @failed_count.to_s },
      "has_flamegraph" => false, "request_method" => @method, "request_path" => @path, "root" => root
    })
  end
end

# Explicit connection decorator, not a global PG patch. Bind values are ONLY
# forwarded to the driver; never retained. Both success and errors are measured.
# Callers must attach a fresh request and clear it in ensure at every boundary.
class SpinelMiniProfilerConnection
  attr_accessor :request

  def initialize(connection)
    @connection = connection
    @request = nil
  end

  def exec(sql)
    active = @request
    return @connection.exec(sql) unless active
    started = SpinelMiniProfiler.clock
    failed = true
    begin
      result = @connection.exec(sql)
      failed = false
      result
    ensure
      active.record(sql, started, failed)
    end
  end

  def exec_params(sql, params)
    active = @request
    return @connection.exec_params(sql, params) unless active
    started = SpinelMiniProfiler.clock
    failed = true
    begin
      result = @connection.exec_params(sql, params)
      failed = false
      result
    ensure
      active.record(sql, started, failed)
    end
  end

  def close
    @connection.close
  end
end

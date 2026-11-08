# frozen_string_literal: true
# Separate full-Rails diagnostic carrier, AFTER the genuine original boot/query.
# NOT native execution, standalone compatibility, or candidate bootstrap proof.
load File.join(__dir__, "core_no_plugins_reference_consumer.rb")
if ENV["FIDELITY_MULTISITE_LOWERED"]
  load ENV.fetch("FIDELITY_MULTISITE_LOWERED")
end

def multisite_nonlocal_result
  RailsMultisite::ConnectionManagement.safe_each_connection { |site| return [site, site.class.name] }
  raise "original nonlocal callback return lost"
end

manager = RailsMultisite::ConnectionManagement
before_env = ENV["RAILS_DB"]
results = []
begin
  [nil, "source-boundary-control"].each do |branch|
    branch ? ENV["RAILS_DB"] = branch : ENV.delete("RAILS_DB")
    calls = []
    value = manager.safe_each_connection { |site| calls << [site, site.class.name, manager.current_db == site]; :callback_result }
    results << {branch: !branch.nil?, callbacks: calls, returned: value, nonlocal: multisite_nonlocal_result}
    # Real callback control transfers across the genuine yield, not replacement
    # iterator/provider methods. The guards are diagnostic safety preconditions,
    # NEVER a runtime assumption or a saved database name for a native input.
    raise SecurityError, "fault controls require ONLY the genuine default site" unless
      manager.current_db == manager::DEFAULT && manager.all_dbs == [manager::DEFAULT]
    results << {branch: !branch.nil?, no_block: manager.safe_each_connection,
                block_break: manager.safe_each_connection { break :block_break_result },
                caught_throw: catch(:multisite_callback_control) {
                  manager.safe_each_connection { |site| throw :multisite_callback_control, [site, site.class.name] }
                  raise "callback throw was lost"
                }}
    [PG::ConnectionBad, PG::UnableToSend, PG::ServerError].each do |error_class|
      seen = []
      returned = manager.safe_each_connection do |site|
        # SecurityError is not caught by the source's StandardError rescue.
        # Refuse before a PG error could enter a nondefault failover branch.
        raise SecurityError, "refuse nondefault failover effects" unless site.instance_of?(String) && site == manager::DEFAULT
        seen << [site, site.class.name]
        raise error_class, "isolated callback fault"
      end
      raise "original PG rescue did not stop after one callback" unless seen.length == 1
      results << {branch: !branch.nil?, rescued_error: error_class.name, callbacks: seen, returned: returned}
    end
    seen = []
    logged = []
    # Observe the genuine source logger without wrapping/removing the rescue or
    # redirecting STDERR. Its exact error line is retained in each process log.
    trace = TracePoint.new(:c_call) do |event|
      if event.self.equal?(STDERR) && event.method_id == :puts
        logged << [event.path.end_with?("/freedom_patches/rails_multisite.rb") ||
                   event.path == ENV["FIDELITY_MULTISITE_LOWERED"], event.method_id]
      end
    end
    begin
      trace.enable
      returned = manager.safe_each_connection do |site|
        seen << [site, site.class.name]
        raise ArgumentError, "isolated standard callback fault"
      end
    ensure
      trace.disable
    end
    raise "original StandardError callback/logging path was removed" unless seen.length == 1 && logged == [[true, :puts]]
    results << {branch: !branch.nil?, rescued_error: "ArgumentError", callbacks: seen,
                returned: returned, genuine_stderr_puts: logged}
  end
ensure
  before_env ? ENV["RAILS_DB"] = before_env : ENV.delete("RAILS_DB")
end
lookup = RailsMultisite::DiscoursePatches.config.fetch(:db_lookup)
value = lookup.call("PATH_INFO" => "/srv/status")
results << {lookup_result: value, lookup_class: value.class.name, literal_frozen: value.frozen?, other_path: lookup.call("PATH_INFO" => "/elsewhere")}
puts "FIDELITY_MULTISITE_RENDERER " + JSON.generate({
  scope: "postboot genuine-source/shared-IR methods on separate full-Rails carriers ONLY; NOT candidate load-order, cold-cache, standalone or native proof",
  lowered: !!ENV["FIDELITY_MULTISITE_LOWERED"], results: results,
  descriptors: [:safe_each_connection, :each_active_connection].to_h { |name|
    method = manager.method(name)
    [name, {arity: method.arity, parameters: method.parameters}]
  },
})

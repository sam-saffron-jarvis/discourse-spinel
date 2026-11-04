# frozen_string_literal: true

# Thread-aware, value-free request context shared by the original trace consumer
# and endpoint guards. A request's main thread is labeled explicitly; concurrent
# threads are only described as overlapping, never causally attributed.
module FidelityOracleObservation
  PHASE_KEY = :fidelity_oracle_phase
  REQUEST_KEY = :fidelity_oracle_request_id

  class << self
    def set_phase(phase)
      Thread.current.thread_variable_set(PHASE_KEY, phase.to_s)
    end

    def begin_request(phase:, request_id:, path:)
      set_phase(phase)
      Thread.current.thread_variable_set(REQUEST_KEY, request_id)
      context = { request_id: request_id, phase: phase.to_s, path: path.to_s,
                  request_thread_id: Thread.current.object_id }
      @active_request = context
      context
    end

    def end_request(request_id)
      @active_request = nil if @active_request && @active_request[:request_id] == request_id
      Thread.current.thread_variable_set(REQUEST_KEY, nil)
    end

    def context
      thread_id = Thread.current.object_id
      request_id = Thread.current.thread_variable_get(REQUEST_KEY)
      phase = Thread.current.thread_variable_get(PHASE_KEY)
      active = @active_request

      if request_id
        { phase: phase || "request", thread_id: thread_id, thread_role: "request",
          request_id: request_id, request_thread_id: thread_id }
      elsif active
        { phase: "concurrent", thread_id: thread_id, thread_role: "concurrent",
          active_request_id: active[:request_id], request_thread_id: active[:request_thread_id] }
      else
        # Do not reuse the process-global phase for a thread that did not receive
        # that phase explicitly. The preflight subprocess is the only env fallback.
        fallback = ENV["FIDELITY_ORACLE_PHASE"] if ENV["FIDELITY_ORACLE_PHASE"] == "preflight"
        { phase: phase || fallback || "background", thread_id: thread_id,
          thread_role: phase || fallback ? "phase_thread" : "background" }
      end
    end

    def original_app_callers(locations, root:, max_frames: 30)
      root = File.expand_path(root)
      prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
      Array(locations).filter_map do |frame|
        path = frame.respond_to?(:absolute_path) ? (frame.absolute_path || frame.path) : frame.to_s.split(":", 2).first
        next unless path
        absolute = File.expand_path(path)
        next unless absolute.start_with?(prefix)

        line = frame.respond_to?(:lineno) ? frame.lineno : frame.to_s.split(":", 3)[1].to_i
        method = frame.respond_to?(:base_label) ? frame.base_label : nil
        { source: absolute.delete_prefix(prefix), line: line, method: method }
      end.first(max_frames)
    end

    # Capture only exception identity and frames owned by this archived source.
    # Messages, response bodies, SQL, arguments, and arbitrary exception data are
    # intentionally excluded.
    def safe_exception(exception, root:, max_causes: 8, max_frames: 40)
      return nil unless exception.is_a?(Exception)

      root = File.expand_path(root)
      prefix = root.end_with?(File::SEPARATOR) ? root : "#{root}#{File::SEPARATOR}"
      causes = []
      current = exception
      seen = {}
      while current && causes.length < max_causes && !seen[current.object_id]
        seen[current.object_id] = true
        causes << current.class.name
        current = current.cause
      end
      frames = Array(exception.backtrace_locations).filter_map do |frame|
        path = frame.absolute_path || frame.path
        next unless path
        absolute = File.expand_path(path)
        next unless absolute.start_with?(prefix)

        { source: absolute.delete_prefix(prefix), line: frame.lineno, method: frame.base_label }
      end.first(max_frames)
      { error_class: exception.class.name, cause_chain: causes, original_app_backtrace: frames }
    end
  end
end

FidelityOracleObservation.set_phase(ENV["FIDELITY_ORACLE_PHASE"]) if ENV["FIDELITY_ORACLE_PHASE"] == "preflight"

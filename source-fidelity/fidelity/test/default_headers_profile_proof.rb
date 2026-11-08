# frozen_string_literal: true
# TEST-only leaves compare the actual DefaultHeaders algorithm and live/source
# configuration on all three runtimes. No response data enters application code.
class DefaultHeadersProfileProof
  def self.run
    cases = [{"Content-Type" => "application/json"},
      {"Content-Type" => "application/json", "X-Content-Type-Options" => "controller-choice"},
      {"Content-Type" => "application/json", "X-Frame-Options" => "DENY", "X-XSS-Protection" => "controller-choice"}]
    rows = []
    cases.each do |input|
      headers = input.dup
      body = ["test leaf body"]
      leaf = lambda { |_env| [200, headers, body] }
      result = Middleware::DefaultHeaders.new(leaf).call({})
      raise "default headers lost response identity" unless result[1].equal?(headers) && result[2].equal?(body)
      raise "default headers dropped controller values" unless input.all? { |key, value| result[1][key] == value }
      raise "excluded frame header was added" if !input.key?("X-Frame-Options") && result[1].key?("X-Frame-Options")
      raise "HTML-only XSS default leaked into JSON" if !input.key?("X-XSS-Protection") && result[1].key?("X-XSS-Protection")
      rows << {input: input, headers: result[1], body: result[2]}
    end
    original_leaf = {"Content-Type" => "application/json"}
    raise "omitted default headers accepted" if rows.first[:headers] == original_leaf
    configuration = if defined?(PortableDefaultHeaderConfiguration)
      PortableDefaultHeaderConfiguration.default_headers
    else
      Rails.application.config.action_dispatch.default_headers.to_h
    end
    if defined?(PortableDefaultHeaderConfiguration)
      refused = false
      begin
        Middleware::DefaultHeaders.new(lambda { |_env| [200, {"Content-Type" => "text/html"}, ["test HTML"]] }).call({})
      rescue ArgumentError => error
        raise unless error.message == "unsupported JSON profile HTML default headers"
        refused = true
      end
      raise "unimplemented HTML policy admitted" unless refused
    end
    puts "FIDELITY_DEFAULT_HEADERS_PROFILE " + JSON.generate({configuration: configuration, rows: rows, omitted_guard_rejected: true})
  end
end

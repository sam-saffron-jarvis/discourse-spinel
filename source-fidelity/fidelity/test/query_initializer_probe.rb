# frozen_string_literal: true
# TEST-only observations of the unchanged original initializer. This never
# calls/replaces a query, permission method, setting reader, provider or plugin.
module InitializerObservation
  def self.run(page, bad_option)
    options = { page: page, per_page: 20 }
    if bad_option
      options[:not_a_query_option] = 1
      begin
        TopicQuery.new(nil, options)
        raise "original key validation did not reject the unknown option"
      rescue ArgumentError => error
        puts "FIDELITY " + FidelityDriver.encode({ kind: "invalid_option", error: error.message })
      end
    else
      query = TopicQuery.new(nil, options)
      raise "options not copied" if query.options.equal?(options)
      raise "options values" unless query.options[:page] == page && query.options[:per_page] == 20
      raise "user identity" unless query.user.nil?
      raise "anonymous identity" if query.guardian.is_admin?
      query.options[:page] = page + 1
      raise "original caller options mutated" unless options[:page] == page
      puts "FIDELITY " + FidelityDriver.encode({ kind: "initializer", input_page: options[:page],
        copied_page: query.options[:page], per_page: query.options[:per_page], admin: query.guardian.is_admin? })
    end
  end
end
if ENV.fetch("FIDELITY_QUERY_MATRIX", "0") == "1"
  InitializerObservation.run(0, false)
  InitializerObservation.run(1, false)
  InitializerObservation.run(0, true)
else
  InitializerObservation.run(ENV.fetch("FIDELITY_QUERY_PAGE", "0").to_i,
                             ENV.fetch("FIDELITY_QUERY_BAD_OPTION", "0") == "1")
end

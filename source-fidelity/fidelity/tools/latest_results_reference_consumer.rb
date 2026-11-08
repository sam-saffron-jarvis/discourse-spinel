require_relative "default_results_reference_consumer"
load ENV.fetch("FIDELITY_LATEST_RESULTS_COMPONENT")
load ENV.fetch("FIDELITY_LATEST_RESULTS_CONSUMER")
class LatestResultsProbe
  def self.build(options)
    TopicQueryLatestResults.validate_options!(options)
    query = TopicQuery.new(nil, options)
    raise "original latest_results source changed" unless query.method(:latest_results).source_location == [File.expand_path("lib/topic_query.rb"), 629]
    query
  end
  def self.results(query, options)
    TopicQueryLatestResults.validate_options!(options)
    TopicQueryLatestResults.validate_options!(query.options, true)
    query.send(:latest_results, options)
  end
end

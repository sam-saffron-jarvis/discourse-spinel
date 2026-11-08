require_relative "visible_page_reference_consumer"
load ENV.fetch("FIDELITY_DEFAULT_RESULTS_COMPONENT")
load ENV.fetch("FIDELITY_DEFAULT_RESULTS_CONSUMER")
class DefaultResultsProbe
  def self.build(options)
    TopicQueryDefaultResults.validate_options!(options)
    query = TopicQuery.new(nil, options)
    raise "original default_results source changed" unless query.method(:default_results).source_location == [File.expand_path("lib/topic_query.rb"), 821]
    query
  end
  def self.results(query, options)
    TopicQueryDefaultResults.validate_options!(options)
    TopicQueryDefaultResults.validate_options!(query.options, true)
    query.send(:default_results, options)
  end
  def self.tags_loaded(record)
    record.association(:tags).loaded?
  end
end

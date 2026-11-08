require_relative "latest_results_reference_consumer"
load ENV.fetch("FIDELITY_LIST_LATEST_COMPONENT")
load ENV.fetch("FIDELITY_LIST_LATEST_CONSUMER")
class ListLatestProbe
  def self.build(options)
    TopicQueryListLatest.validate_options!(options)
    query = TopicQuery.new(nil, options)
    raise "original list_latest source changed" unless query.method(:list_latest).source_location == [File.expand_path("lib/topic_query.rb"), 305]
    query
  end
  def self.list(query)
    TopicQueryListLatest.validate_options!(query.options, true)
    query.list_latest
  end
  def self.loaded(record)
    [:category, :image_upload, :topic_thumbnails, :first_post].all? { |name| record.association(name).loaded? }
  end
end

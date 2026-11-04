# frozen_string_literal: true
# Observe the original full Rails methods, not the projected definitions.
{
  TopicQuery.instance_method(:initialize) => ["lib/topic_query.rb", 145],
  TopicQuery.method(:valid_options) => ["lib/topic_query.rb", 91],
  TopicQuery.method(:public_valid_options) => ["lib/topic_query.rb", 62],
  Guardian.instance_method(:initialize) => ["lib/guardian.rb", 122],
  Guardian.instance_method(:is_admin?) => ["lib/guardian.rb", 140],
  Guardian::AnonymousUser.instance_method(:admin?) => ["lib/guardian.rb", 44],
}.each do |method, (path, line)|
  raise "applicable original owner changed; expand closure" unless method.source_location == [File.expand_path(path), line]
end

# Observation only: identify real post-boot producers of the constructor's
# accepted option state. Never copy these values back into native execution.
filters = TopicQuery.instance_variable_get(:@custom_filters)
puts "FIDELITY_QUERY_REGISTRATIONS " + JSON.generate({
  valid_options: TopicQuery.valid_options.map(&:to_s),
  filters: filters.to_h.transform_values { |callback| callback.source_location },
  scope: "actual Rails post-boot registration inventory ONLY; not a native seed",
})

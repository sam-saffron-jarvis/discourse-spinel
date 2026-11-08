# Observation only: calls the real full query, never supplies rows/settings.
puts "FIDELITY_LATEST_QUERY_ENTER"
list = TopicQuery.new(nil, per_page: 20).list_latest
rows = list.topics.map do |topic|
  values = [topic.id, topic.slug, topic.title, topic.category_id]
  [values, values.map { |value| value.class.name }]
end
puts "FIDELITY_LATEST_EXECUTION " + JSON.generate({rows: rows})

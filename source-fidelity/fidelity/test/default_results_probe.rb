module DefaultResultsObservation
  def self.emit(name, initial_options, call_options, fixture)
    if ENV.fetch("FIDELITY_STAGE2_WRONG_ORDER", "0") == "1" && name == "fixture_default"
      initial_options[:order] = "views"
    end
    if ENV.fetch("FIDELITY_STAGE2_WRONG_CATEGORY", "0") == "1" && name == "fixture_category"
      initial_options[:category] = DefaultResultsProbe.other_category_id.to_s
    end
    before = initial_options.dup
    query = DefaultResultsProbe.build(initial_options)
    relation = DefaultResultsProbe.results(query, call_options)
    raise "constructor mutated original options" unless initial_options == before
    relation = DefaultResultsProbe.fixture(relation) if fixture
    rows = relation.to_a
    observed = []
    repeat = FidelityDriver.capture do
      observed = rows.map do |row|
        raise "default_results category not hydrated" unless FidelityDriver.category_loaded(row)
        category = row.category
        raise "default_results category identity" if category && category.id != row.category_id
        tags = []
        if SiteSetting.tagging_enabled
          raise "default_results tags not preloaded" unless DefaultResultsProbe.tags_loaded(row)
          tags = row.tags.to_a.sort_by(&:id).map { |tag| [tag.id, tag.name, tag.slug, tag.id.class.name] }
        end
        {id: row.id, title: row.title, visible: row.visible, archetype: row.archetype,
         category_id: row.category_id, category_name: category.nil? ? nil : category.name,
         bumped_at: FidelityDriver.timestamp(row.bumped_at), created_at: FidelityDriver.timestamp(row.created_at),
         views: row.views, posts_count: row.posts_count, tags: tags,
         id_type: row.id.class.name, visible_type: row.visible.class.name,
         category_loaded: FidelityDriver.category_loaded(row)}
      end
    end
    raise "reading hydrated default_results associations queried" unless repeat.empty?
    puts "FIDELITY " + FidelityDriver.encode({kind: "stage2_rows", name: name, options: call_options,
      query_options: query.options, tagging: SiteSetting.tagging_enabled, rows: observed})
  end
end
puts "FIDELITY_STAGE2_QUERY_ENTER"
DefaultResultsObservation.emit("live_default", {}, {per_page: 3}, false)
DefaultResultsObservation.emit("live_page1", {}, {per_page: 3, page: 1}, false)
DefaultResultsObservation.emit("live_views", {order: "views", ascending: "true"}, {per_page: 4}, false)
DefaultResultsObservation.emit("live_category", {category: DefaultResultsProbe.category_id.to_s}, {per_page: 5}, false)
DefaultResultsObservation.emit("live_category_slug", {category: DefaultResultsProbe.category_slug, no_subcategories: "true"}, {per_page: 5}, false)
DefaultResultsObservation.emit("live_restricted_category", {category: DefaultResultsProbe.restricted_category_id.to_s, no_subcategories: true}, {per_page: 5}, false)
DefaultResultsObservation.emit("live_no_definitions", {no_definitions: true}, {per_page: 5}, false)
DefaultResultsObservation.emit("live_no_tags", {no_tags: true}, {per_page: 5}, false)
DefaultResultsObservation.emit("fixture_default", {}, {per_page: 5}, true)
DefaultResultsObservation.emit("fixture_page0", {}, {per_page: 2, page: 0}, true)
DefaultResultsObservation.emit("fixture_page1", {}, {per_page: 2, page: 1}, true)
DefaultResultsObservation.emit("fixture_views", {order: "views"}, {per_page: 5}, true)
DefaultResultsObservation.emit("fixture_created", {order: "created", ascending: "true"}, {per_page: 5}, true)
DefaultResultsObservation.emit("fixture_category", {category: DefaultResultsProbe.category_id.to_s, order: "activity"}, {per_page: 5}, true)
DefaultResultsObservation.emit("fixture_except", {except_topic_ids: [110, 105]}, {per_page: 5}, true)
DefaultResultsObservation.emit("fixture_ids", {topic_ids: [101, 108, 110]}, {per_page: 5}, true)
DefaultResultsObservation.emit("fixture_max_posts", {max_posts: 8}, {per_page: 5}, true)
[{search: "unsupported"}, {state: "muted"}, {status: "closed"}, {include_pms: true}, {tags: ["tag"]},
 {skip_ordering: true}, {order: "op_likes"}, {guardian: nil}].each do |options|
  rejected = false
  queries = FidelityDriver.capture do
    begin
      DefaultResultsProbe.build(options)
    rescue ArgumentError
      rejected = true
    end
  end
  raise "unsupported default_results profile accepted" unless rejected
  raise "unsupported default_results profile queried" unless queries.empty?
  puts "FIDELITY " + FidelityDriver.encode({kind: "stage2_refusal", option: options.keys.first.to_s, rejected: true, query_count: 0})
end
query = DefaultResultsProbe.build({})
query.options[:search] = "unsupported mutation"
rejected = false
queries = FidelityDriver.capture do
  begin
    DefaultResultsProbe.results(query, {})
  rescue ArgumentError
    rejected = true
  end
end
raise "mutated unsupported profile accepted" unless rejected && queries.empty?
puts "FIDELITY " + FidelityDriver.encode({kind: "stage2_refusal", option: "mutated_search", rejected: true, query_count: 0})
puts "FIDELITY_STAGE2_MATERIALIZED"

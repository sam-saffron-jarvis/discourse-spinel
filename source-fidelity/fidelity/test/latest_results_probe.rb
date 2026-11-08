module LatestResultsObservation
  def self.emit(name, initial_options, call_options, fixture, callback_unit)
    callbacks = TopicQuery.results_filter_callbacks
    before_count = callbacks.length
    saved = callbacks.dup
    begin
      if callback_unit
        callback = lambda do |filter, relation, user, options|
          raise "result callback filter" unless filter == :latest
          raise "result callback identity" unless user.nil?
          raise "result callback mutated options" unless options[:visible] == true
          if ENV.fetch("FIDELITY_STAGE3A_WRONG_CALLBACK", "0") == "1"
            relation
          else
            relation.where("topics.id <> ?", 110)
          end
        end
        callbacks << callback
      end
      query = LatestResultsProbe.build(initial_options)
      relation = LatestResultsProbe.results(query, call_options)
      relation = DefaultResultsProbe.fixture(relation) if fixture
      rows = relation.to_a
      observed = []
      repeat = FidelityDriver.capture do
        observed = rows.map do |row|
          raise "latest category preload" unless FidelityDriver.category_loaded(row)
          category = row.category
          tags = []
          if SiteSetting.tagging_enabled
            raise "latest tag preload" unless DefaultResultsProbe.tags_loaded(row)
            tags = row.tags.to_a.sort_by(&:id).map { |tag| [tag.id, tag.name, tag.slug] }
          end
          {id: row.id, title: row.title, visible: row.visible, category_id: row.category_id,
           category_name: category.nil? ? nil : category.name, tags: tags,
           bumped_at: FidelityDriver.timestamp(row.bumped_at), id_type: row.id.class.name}
        end
      end
      raise "latest association read queried" unless repeat.empty?
      puts "FIDELITY " + FidelityDriver.encode({kind: "stage3a_rows", name: name, options: call_options,
        query_options: query.options, callback_registry_before: before_count, callback_unit: callback_unit,
        mute_all_categories_by_default: SiteSetting.mute_all_categories_by_default,
        default_categories_muted: SiteSetting.default_categories_muted, default_tags_muted: SiteSetting.default_tags_muted,
        remove_muted_tags_from_latest: SiteSetting.remove_muted_tags_from_latest, shared_drafts_category: SiteSetting.shared_drafts_category,
        rows: observed})
    ensure
      callbacks.replace(saved)
      raise "callback registry not restored" unless callbacks.length == before_count
    end
  end
end
puts "FIDELITY_STAGE3A_QUERY_ENTER"
LatestResultsObservation.emit("live_latest", {}, {per_page: 3}, false, false)
LatestResultsObservation.emit("live_latest_page1", {}, {per_page: 3, page: 1}, false, false)
LatestResultsObservation.emit("live_latest_category", {category: DefaultResultsProbe.category_id.to_s}, {per_page: 5}, false, false)
LatestResultsObservation.emit("fixture_latest", {}, {per_page: 5}, true, false)
LatestResultsObservation.emit("fixture_latest_page1", {}, {per_page: 2, page: 1}, true, false)
LatestResultsObservation.emit("fixture_callback", {}, {per_page: 5}, true, true)
puts "FIDELITY_STAGE3A_MATERIALIZED"

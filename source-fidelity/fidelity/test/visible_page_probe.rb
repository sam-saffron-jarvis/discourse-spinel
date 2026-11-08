# Stage1 observations, cumulative with the original Stage0 security probe above.
module VisiblePageObservation
  def self.emit(name, options, fixture)
    if ENV.fetch("FIDELITY_STAGE1_WRONG_PAGE", "0") == "1" && name == "fixture_page0"
      options[:page] = 1
    end
    relation = fixture ? VisiblePageProbe.fixture_relation(options) : VisiblePageProbe.relation(options).order("topics.id ASC")
    rows = relation.to_a
    raise "stage1 category preload" unless rows.all? { |row| FidelityDriver.category_loaded(row) }
    observed = rows.map do |row|
      category = row.category
      raise "stage1 category identity" if category && category.id != row.category_id
      visible = ENV.fetch("FIDELITY_STAGE1_WRONG_TYPE", "0") == "1" ? 1 : row.visible
      {id: row.id, title: row.title, archetype: row.archetype, visible: visible,
       category_id: row.category_id, category_name: category.nil? ? nil : category.name,
       deleted_at: FidelityDriver.timestamp(row.deleted_at), id_type: row.id.class.name,
       visible_type: row.visible.class.name, category_id_type: row.category_id.class.name,
       category_loaded: FidelityDriver.category_loaded(row)}
    end
    puts "FIDELITY " + FidelityDriver.encode({kind: "stage1_rows", name: name,
      options: {page: options[:page], per_page: options[:per_page], visible: options[:visible], limit: options[:limit]}, rows: observed})
  end
end
puts "FIDELITY_STAGE1_QUERY_ENTER"
VisiblePageObservation.emit("live_page0", {page: 0, per_page: 2}, false)
VisiblePageObservation.emit("live_page1", {page: 1, per_page: 2}, false)
VisiblePageObservation.emit("fixture_default", {}, true)
VisiblePageObservation.emit("fixture_page0", {page: 0, per_page: 2}, true)
VisiblePageObservation.emit("fixture_page1", {page: 1, per_page: 2}, true)
VisiblePageObservation.emit("fixture_page2", {page: 2, per_page: 2}, true)
VisiblePageObservation.emit("fixture_per3", {page: 1, per_page: 3}, true)
VisiblePageObservation.emit("fixture_unlimited", {limit: false}, true)
[{search: "unsupported"}, {category: "unsupported"}, {include_pms: true}, {order: "views"},
 {visible: false}, {page: -1}, {per_page: 0}].each do |options|
  rejected = false
  queries = FidelityDriver.capture do
    begin
      VisiblePageProbe.relation(options)
    rescue ArgumentError
      rejected = true
    end
  end
  raise "unsupported stage1 request accepted" unless rejected
  raise "unsupported stage1 request queried" unless queries.empty?
  puts "FIDELITY " + FidelityDriver.encode({kind: "stage1_refusal", option: options.keys.first.to_s,
    query_count: queries.length, rejected: rejected})
end
puts "FIDELITY_STAGE1_MATERIALIZED"

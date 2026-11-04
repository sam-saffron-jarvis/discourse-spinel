# frozen_string_literal: true
# Shared TEST observations. The native/compat side loads the identical lowered
# Ruby; the separate actual Rails process loads unchanged complete models.
module ScopeObservation
  def self.row(kind, record)
    category = record.category
    raise "id type" unless record.id.is_a?(Integer)
    raise "title type" unless record.title.is_a?(String)
    raise "archetype type" unless record.archetype.is_a?(String)
    raise "score type" unless record.score.nil? || record.score.is_a?(Float)
    raise "percent_rank type" unless record.percent_rank.is_a?(Float)
    raise "excerpt type" unless record.excerpt.nil? || record.excerpt.is_a?(String)
    raise "user_id type" unless record.user_id.nil? || record.user_id.is_a?(Integer)
    raise "timestamp type" unless record.created_at.is_a?(Time)
    raise "association not preloaded" unless FidelityDriver.category_loaded(record)
    raise "category type" unless record.category_id.nil? || record.category_id.is_a?(Integer)
    name = category.nil? ? nil : category.name
    puts "FIDELITY {\"kind\":" + FidelityDriver.encode(kind) + ",\"id\":" + FidelityDriver.encode(record.id) +
      ",\"title\":" + FidelityDriver.encode(record.title) +
      ",\"archetype\":" + FidelityDriver.encode(record.archetype) +
      ",\"visible\":" + FidelityDriver.encode(record.visible) +
      ",\"category_id\":" + FidelityDriver.encode(record.category_id) +
      ",\"category_name\":" + FidelityDriver.encode(name) +
      ",\"score\":" + FidelityDriver.encode(record.score) +
      ",\"percent_rank\":" + FidelityDriver.encode(record.percent_rank) +
      ",\"excerpt\":" + FidelityDriver.encode(record.excerpt) +
      ",\"user_id\":" + FidelityDriver.encode(record.user_id) +
      ",\"created_at\":" + FidelityDriver.encode(FidelityDriver.timestamp(record.created_at)) +
      ",\"deleted_at\":" + FidelityDriver.encode(FidelityDriver.timestamp(record.deleted_at)) + "}"
  end
end

relation = nil
compose = FidelityDriver.capture do
  relation = ScopeProbe.relation
  raise "default scope disappeared" unless relation.to_sql.include?("deleted_at")
end
raise "query executed while composing" unless compose.empty?
rows = []
load_queries = FidelityDriver.capture { rows = relation.to_a }
raise "expected nonempty live slice" if rows.empty?
raise "category preload not batched" unless load_queries.length == 2
repeat_queries = FidelityDriver.capture do
  again = relation.to_a
  raise "memoized rows changed" unless again.length == rows.length
  rows.each do |record|
    raise "visible type/value" unless record.visible == true && record.visible.is_a?(TrueClass)
    raise "default NULL predicate" unless record.deleted_at.nil?
    raise "private messages leaked" if record.archetype == Archetype.private_message
    raise "live category missing" if record.category.nil?
    raise "category identity" unless record.category.id == record.category_id
    ScopeObservation.row("row", record)
  end
end
raise "cached rows/associations issued queries" unless repeat_queries.empty?
raise "limit fork mutated parent" unless relation.limit(1).to_a.length == 1 && relation.to_a.length == rows.length
attack = "O'Reilly? ' OR TRUE --"
raise "bound string became SQL" unless Topic.listable_topics.visible.where("topics.title = ?", attack).to_a.empty?

# SELECT-only derived fixture. These are NOT claimed as live records. A second
# execution of the same native binary deliberately omits the original visible
# scope in the TEST consumer; the comparator must reject its actual query rows.
fixture = ENV.fetch("FIDELITY_NEGATIVE_SCOPE", "0") == "1" ? ScopeProbe.wrong_scope_relation : ScopeProbe.fixture_relation
fixture_rows = []
fixture_queries = FidelityDriver.capture { fixture_rows = fixture.to_a }
raise "fixture preload not batched" unless fixture_queries.length == 2
fixture_repeat = FidelityDriver.capture do
  fixture_rows.each { |record| ScopeObservation.row("fixture", record) }
  fixture.to_a
end
raise "fixture associations issued queries" unless fixture_repeat.empty?
# These binds operate over controlled rows, not assumptions about live titles.
puts "FIDELITY {\"kind\":\"fixture_bind\",\"matched\":" + ScopeProbe.fixture_relation.where("topics.title = ?", fixture_rows[0].title).to_a.length.to_s + "}"
puts "FIDELITY {\"kind\":\"fixture_null\",\"matched\":" + ScopeProbe.fixture_relation.where(category_id: nil).to_a.length.to_s + "}"
begin
  Topic.find(nil)
  raise "find(nil) returned successfully"
rescue ActiveRecord::RecordNotFound
  puts 'FIDELITY {"kind":"exception","name":"ActiveRecord::RecordNotFound"}'
end
begin
  Topic.listable_topics.limit("not-an-integer")
  raise "invalid limit returned successfully"
rescue ArgumentError
  puts 'FIDELITY {"kind":"exception","name":"ArgumentError"}'
end
puts "FIDELITY {\"kind\":\"queries\",\"compose\":" + compose.length.to_s + ",\"materialize\":" + load_queries.length.to_s +
  ",\"repeat\":" + repeat_queries.length.to_s + ",\"fixture\":" + fixture_queries.length.to_s + ",\"fixture_repeat\":" + fixture_repeat.length.to_s + "}"
# Last database operation: PG aborts the native read-only transaction on this
# SELECT error; its driver must surface an error, never successful empty rows.
begin
  Topic.listable_topics.where("source_fidelity_missing_column = 1").to_a
  raise "invalid SELECT returned successfully"
rescue ActiveRecord::StatementInvalid
  puts 'FIDELITY {"kind":"exception","name":"ActiveRecord::StatementInvalid"}'
end

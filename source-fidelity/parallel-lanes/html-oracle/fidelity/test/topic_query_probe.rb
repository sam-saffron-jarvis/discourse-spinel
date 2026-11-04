# frozen_string_literal: true
# Shared TEST observations, explicitly only the anonymous partial expression.
module SecurityObservation
  def self.row(kind, record)
    raise "id type" unless record.id.is_a?(Integer)
    raise "title type" unless record.title.is_a?(String)
    raise "category preload" unless FidelityDriver.category_loaded(record)
    category = record.category
    raise "category identity" if category && category.id != record.category_id
    puts "FIDELITY " + FidelityDriver.encode({kind: kind, id: record.id, title: record.title,
      archetype: record.archetype, visible: record.visible, category_id: record.category_id,
      category_name: category.nil? ? nil : category.name,
      deleted_at: FidelityDriver.timestamp(record.deleted_at)})
  end
end

guardian = Guardian.new
# The executed original filter reaches initialize/is_admin?, not anonymous? or
# authenticated?. Its actual input is Guardian.new(nil), with the ORIGINAL
# AnonymousUser fallback and methods, never a synthetic permission object.
raise "anonymous admin predicate" if guardian.is_admin?
ids = []
first_permission = FidelityDriver.capture { ids = guardian.allowed_category_ids }
raise "no live category visibility input" if ids.empty?
raise "permission query" unless first_permission.length == 1
cached_permission = FidelityDriver.capture do
  raise "permission cache changed" unless guardian.allowed_category_ids == ids
  raise "anonymous secured categories" unless guardian.secure_category_ids.empty?
end
raise "permission not memoized" unless cached_permission.empty?
puts "FIDELITY " + FidelityDriver.encode({kind: "permission", ids: ids.sort, identity_input: "Guardian.new(nil)", admin: guardian.is_admin?})
relation = nil
compose = FidelityDriver.capture { relation = SecurityProbe.relation.order("topics.id ASC").limit(5) }
# Permission discovery executes once during original composition; topic rows
# remain lazy. Unlike018, zero queries here would mean permissions were frozen.
raise "missing permission discovery" unless compose.length == 1
rows = []
materialize = FidelityDriver.capture { rows = relation.to_a }
raise "empty live path" if rows.empty?
repeated = FidelityDriver.capture { rows.each { |row| SecurityObservation.row("row", row) }; relation.to_a }
raise "live association/cache query" unless repeated.empty?
raise "limit fork changed receiver" unless relation.limit(1).to_a.length == 1 && relation.to_a.length == rows.length
fixture = ENV.fetch("FIDELITY_NEGATIVE_SCOPE", "0") == "1" ? SecurityProbe.wrong_scope_relation : SecurityProbe.fixture_relation
fixture_rows = []
fixture_queries = FidelityDriver.capture { fixture_rows = fixture.to_a }
fixture_cached = FidelityDriver.capture { fixture_rows.each { |row| SecurityObservation.row("fixture", row) }; fixture.to_a }
raise "fixture association/cache query" unless fixture_cached.empty?
raise "missing NULL category" unless fixture_rows.any? { |r| r.category_id.nil? }
raise "missing dangling category" unless fixture_rows.any? { |r| r.category_id == -987654321 && r.category.nil? }
# Arrays in original positional IN (?) binds are lists, not quoted Ruby arrays.
attack = ["O'Reilly? \\ literal", "' OR TRUE --"]
raise "quote/list bind" unless SecurityProbe.fixture_relation.where("topics.title IN (?)", attack).to_a.empty?
raise "empty list bind" unless SecurityProbe.fixture_relation.where("topics.id IN (?)", []).to_a.empty?
puts "FIDELITY " + FidelityDriver.encode({kind: "bind", empty: true, hostile: true})
puts "FIDELITY_QUERY " + FidelityDriver.encode({compose: compose.length, materialize: materialize.length,
  repeat: repeated.length, fixture: fixture_queries.length, fixture_repeat: fixture_cached.length,
  limitation: "compat batch preload vs Rails joined-row hydration; not asserted equivalent"})

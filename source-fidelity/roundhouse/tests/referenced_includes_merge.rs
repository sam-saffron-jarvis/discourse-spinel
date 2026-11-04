//! A referenced include can arrive via an argument/merge after includes was
//! composed. No chain-local rewrite sees both. All writes are SQLite :memory:.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("db/schema.rb", "ActiveRecord::Schema.define do\n  create_table \"shelves\" do |t|\n    t.string \"name\"\n  end\n  create_table \"books\" do |t|\n    t.string \"title\"\n    t.integer \"shelf_id\"\n  end\nend\n")
        .write("app/models/shelf.rb", "class Shelf < ActiveRecord::Base\n  has_many :books\nend\n")
        .write("app/models/book.rb", "class Book < ActiveRecord::Base\n  belongs_to :shelf, optional: true\nend\n")
        .write("app/models/reference_probe.rb", r#"class ReferenceProbe
  def self.condition(records, ids)
    records.where("shelves.id IS NULL OR shelves.id IN (?)", ids).references(:shelves)
  end
  def self.relation(ids)
    Book.includes(:shelf).merge(condition(Book.unscoped, ids))
  end
end
"#)
}

const PROBE: &str = r#"
allowed = Shelf.create!(name: "O'Reilly?")
restricted = Shelf.create!(name: "restricted")
Book.create!(title: "public", shelf_id: allowed.id)
Book.create!(title: "restricted", shelf_id: restricted.id)
Book.create!(title: "null", shelf_id: nil)
Book.create!(title: "dangling", shelf_id: -987)
base = Book.includes(:shelf)
condition = ReferenceProbe.condition(Book.unscoped, [allowed.id])
relation = nil
compose = Db.capture_sql { relation = base.merge(condition).order("books.id ASC") }
raise "not lazy" unless compose.empty?
raise "lost reference" unless relation.to_sql.include?("LEFT OUTER JOIN shelves")
raise "mutated receiver" if base.to_sql.include?("JOIN")
raise "mutated operand" if condition.to_sql.include?("JOIN")
rows = []
queries = Db.capture_sql { rows = relation.to_a }
raise "filter: #{relation.to_sql}; #{rows.map(&:title).inspect}" unless rows.map(&:title) == ["public", "null", "dangling"]
# Explicitly batch preloaded, not joined-row hydration: parent SELECT + target.
raise "batch count" unless queries.length == 2
cached = Db.capture_sql do
  raise "category" unless rows[0].shelf.name == "O'Reilly?"
  raise "NULL" unless rows[1].shelf.nil?
  raise "dangling" unless rows[2].shelf.nil?
  relation.to_a
end
raise "preload/memo" unless cached.empty?
raise "callee composition" unless ReferenceProbe.relation([restricted.id]).order("books.id ASC").to_a.map(&:title) == ["restricted", "null", "dangling"]
fork = relation.references(:unknown)
raise "fork reference list shared" unless relation.reference_values == ["shelves"] && fork.reference_values == ["shelves", "unknown"]
raise "unrelated reference changed SQL" unless fork.to_sql == relation.to_sql
# Caller-owned arrays returned by the metadata reader cannot mutate the scope.
values = condition.reference_values
values.clear
raise "reference_values exposed state" unless relation.to_sql.include?("LEFT OUTER JOIN shelves")
# Preload must not become a join merely because references is present.
raise "preload joined" if Book.preload(:shelf).references(:shelves).to_sql.include?("JOIN")
# Supplying references before includes has the same filtering contract.
raise "order dependent" unless Book.references("shelves").includes(:shelf).where("shelves.name = ?", "O'Reilly?").to_a.map(&:title) == ["public"]
raise "duplicate join" unless Book.joins("INNER JOIN shelves ON shelves.id = books.shelf_id").includes(:shelf).references(:shelves).to_sql.scan("JOIN shelves").length == 1
raise "count" unless relation.where("books.id > ?", 0).count == 3
raise "pluck" unless relation.pluck(:title) == ["public", "null", "dangling"]
raise "exists" unless relation.exists?
raise "positional quoted array" unless Shelf.where("shelves.name IN (?)", ["O'Reilly?", "' OR TRUE --", "back\\slash?"]).to_a.map(&:id) == [allowed.id]
raise "positional empty array" unless Shelf.where("shelves.id IN (?)", []).to_a.empty?
raise "named empty array" unless Shelf.where("shelves.id IN (:ids)", ids: []).to_a.empty?
raise "NULL list member" unless Shelf.where("shelves.id IN (?)", [nil, allowed.id]).to_a.map(&:id) == [allowed.id]
begin
  Book.includes(:shelf).references(:shelf).to_sql
  raise "alias tracking silently guessed"
rescue NotImplementedError
end
begin
  # Through an argument so the existing chain-local has_many lowering does
  # not rewrite this into a different (already supported) representation.
  ReferenceProbe.condition(Shelf.includes(:books), [allowed.id]).references(:books).to_sql
  raise "collection silently joined"
rescue NotImplementedError
end
puts "referenced includes preserved"
"#;

#[test]
fn referenced_includes_across_merge_run_on_emitted_ruby() {
    let run = app().run_ruby(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "referenced includes preserved\n");
}

#[test]
#[ignore = "requires Spinel"]
fn referenced_includes_across_merge_run_natively() {
    let run = app().run_spinel_with_rbs(&format!(
        "Db.configure(\":memory:\")\nSchema.statements.each {{ |sql| Db.exec(sql) }}\nActiveRecord.adapter = SqliteAdapter\n{PROBE}"
    ));
    run.assert_passes();
    assert_eq!(run.stdout, "referenced includes preserved\n");
}

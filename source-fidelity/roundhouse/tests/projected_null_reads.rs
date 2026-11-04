//! Raw FROM rows can null physically NOT NULL attributes. Keep that distinct
//! from the DDL constraint and exercise identical emitted/native scalar reads.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("db/schema.rb", "ActiveRecord::Schema.define do\n  create_table \"samples\" do |t|\n    t.boolean \"active\", null: false\n    t.integer \"quantity\", null: false\n    t.float \"score\", null: false\n    t.string \"label\", null: false\n  end\n  create_table \"identities\" do |t|\n  end\nend\n")
        .write("app/models/identity.rb", "class Identity < ActiveRecord::Base\nend\n")
        .write("app/models/sample.rb", r#"class Sample < ActiveRecord::Base
  def self.projected
    from("(SELECT 1 AS id, NULL AS active, NULL AS quantity, NULL AS score, NULL AS label UNION ALL SELECT 2, 0, 0, 0.0, '' UNION ALL SELECT 3, 1, 7, 1.25, 'yes') AS samples").order("samples.id ASC")
  end
end
"#)
}

const PROBE: &str = r#"
relation = nil
compose = Db.capture_sql { relation = Sample.projected }
raise "not lazy" unless compose.empty?
rows = relation.to_a
raise "rows" unless rows.length == 3
raise "NULL boolean" unless rows[0].active.nil?
raise "NULL integer" unless rows[0].quantity.nil?
raise "NULL float" unless rows[0].score.nil?
raise "NULL text" unless rows[0].label.nil?
raise "false was nil" unless rows[1].active == false && !rows[1].active.nil?
raise "zero" unless rows[1].quantity == 0 && rows[1].score == 0.0
raise "empty text" unless rows[1].label == ""
raise "values" unless rows[2].active == true && rows[2].quantity == 7 && rows[2].score == 1.25 && rows[2].label == "yes"
raise "scalar types" unless rows[1].id.is_a?(Integer) && rows[1].quantity.is_a?(Integer) && rows[1].score.is_a?(Float) && rows[1].label.is_a?(String) && rows[1].active.is_a?(FalseClass) && rows[2].active.is_a?(TrueClass)
repeat = Db.capture_sql { relation.to_a }
raise "cache" unless repeat.empty?
hash_record = Sample.instantiate({"id" => "4", "active" => nil, "quantity" => nil, "score" => nil, "label" => nil})
raise "Hash-row NULLs" unless hash_record.id == 4 && hash_record.active.nil? && hash_record.quantity.nil? && hash_record.score.nil? && hash_record.label.nil?
# Physical NOT NULL is not weakened by the read-shape metadata.
raise "DDL lost NOT NULL" unless Schema.statements.join.include?("active BOOLEAN NOT NULL") || Schema.statements.join.include?("active INTEGER NOT NULL")
begin
  Db.exec("INSERT INTO samples (active, quantity, score, label) VALUES (NULL, 1, 1.0, 'invalid')")
  raise "physical constraint accepted NULL"
rescue StandardError => error
  raise "physical constraint failure was not NOT NULL: #{error.message}" unless error.message.include?("NOT NULL constraint failed")
end
begin
  Sample.projected.from("(SELECT NULL AS id, NULL AS active, NULL AS quantity, NULL AS score, NULL AS label) AS samples").to_a
  raise "NULL identity became a fabricated record"
rescue NotImplementedError
end
begin
  Sample.instantiate({"id" => nil, "active" => nil, "quantity" => nil, "score" => nil, "label" => nil})
  raise "NULL Hash-row identity became a fabricated record"
rescue NotImplementedError
end
begin
  Identity.from("(SELECT NULL AS id) AS identities").to_a
  raise "NULL identity in an id-only schema became a fabricated record"
rescue NotImplementedError
end
puts "projected NULLs preserved"
"#;

#[test]
fn projected_nulls_run_on_emitted_ruby() {
    let result = app().run_ruby(PROBE);
    result.assert_passes();
    assert_eq!(result.stdout, "projected NULLs preserved\n");
}

#[test]
#[ignore = "requires Spinel"]
fn projected_nulls_run_natively() {
    let result = app().run_spinel_with_rbs(&format!(
        "Db.configure(\":memory:\")\nSchema.statements.each {{ |sql| Db.exec(sql) }}\nActiveRecord.adapter = SqliteAdapter\n{PROBE}"
    ));
    result.assert_passes();
    assert_eq!(result.stdout, "projected NULLs preserved\n");
}

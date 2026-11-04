//! Non-null Float writer slots must satisfy the String escape primitive.
//! All persistence here is isolated SQLite :memory:, never task PostgreSQL.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("db/schema.rb", "ActiveRecord::Schema.define do\n  create_table \"measurements\" do |t|\n    t.float \"reading\", null: false\n    t.float \"optional_reading\"\n  end\nend\n")
        .write("app/models/measurement.rb", "class Measurement < ActiveRecord::Base\nend\n")
}

const PROBE: &str = r#"
record = Measurement.create!(reading: 1.25, optional_reading: nil)
found = Measurement.find(record.id)
raise "float insert/type" unless found.reading.is_a?(Float) && found.reading == 1.25
raise "nullable float NULL" unless found.optional_reading.nil?
found.update!(reading: -2.5, optional_reading: 3.75)
found.reload
raise "float update/type" unless found.reading.is_a?(Float) && found.reading == -2.5
raise "nullable float value" unless found.optional_reading == 3.75
puts "float writes preserved"
"#;

#[test]
fn non_null_float_writes_run_on_emitted_ruby() {
    let run = app().run_ruby(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "float writes preserved\n");
}

#[test]
#[ignore = "requires Spinel"]
fn non_null_float_writes_run_natively_with_emitted_signatures() {
    let run = app().run_spinel_with_rbs(&format!(
        "Db.configure(\":memory:\")\nSchema.statements.each {{ |sql| Db.exec(sql) }}\nActiveRecord.adapter = SqliteAdapter\n{PROBE}"
    ));
    run.assert_passes();
    assert_eq!(run.stdout, "float writes preserved\n");
}

//! PostgreSQL selection on Spinel, without creating/seeding any database.
//! The optional native case uses only VALUES/SELECT in a read-only transaction.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

use roundhouse::project::BuildTarget;
use std::process::Command;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/database.yml", "test:\n  adapter: postgresql\n  database: probe\n")
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("db/schema.rb", "ActiveRecord::Schema.define do\n  create_table \"widgets\" do |t|\n    t.string \"name\"\n    t.boolean \"active\"\n    t.float \"score\", null: false\n  end\nend\n")
        .write("app/models/widget.rb", "class Widget < ActiveRecord::Base\n  scope :active, -> { where(active: true) }\nend\n")
}

fn read(root: &std::path::Path, path: &str) -> String {
    std::fs::read_to_string(root.join(path)).unwrap_or_else(|e| panic!("{path}: {e}"))
}

#[test]
fn postgresql_spinel_selects_native_driver_dialect_and_signatures() {
    let (tree, errors) = app().emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    assert!(read(&tree, "runtime/db.rb").contains("Primitive Db surface over PostgreSQL"));
    assert!(read(&tree, "runtime/pg_driver.rb").contains("PG.connect(host, port, database, user, password)"));
    assert!(!tree.join("runtime/pg_driver_cruby.rb").exists());
    assert!(read(&tree, "runtime/pg_errors.rb").contains("StatementInvalid"));
    assert!(read(&tree, "spin.toml").contains("pg = \"0.2.0\""));
    assert!(read(&tree, "runtime/db.rbs").contains("class PgConfig"));
    assert!(read(&tree, "runtime/pg_driver.rbs").contains("PgClientCore"));
    assert!(read(&tree, "config/schema.rb").contains("bigserial PRIMARY KEY"));
    assert!(read(&tree, "main.rb").contains("ENV.fetch(\"DATABASE_URL\", \"\")"));
    // Do not silently run the SQLite test helper on a shared PG database.
    assert!(read(&tree, "test/test_helper.rb").contains("native PostgreSQL test database isolation is not implemented"));
    let widget = read(&tree, "app/models/widget.rb");
    assert!(!widget.contains("WHERE id = ?"), "SQLite placeholders in PG readers");
    assert!(widget.contains("Db.escape_string(@score.to_s)"), "Float passed to String Db slot:\n{widget}");
}

#[test]
fn sqlite_function_registration_is_refused_for_spinel_postgresql() {
    let (_tree, errors) = app()
        .write("config/initializers/sqlite.rb", "conn.create_function(\"regexp\", 2) do |fn, pattern, expr|\n  fn.result = 1\nend\n")
        .emit(BuildTarget::Spinel);
    assert!(errors.iter().any(|e| e.contains("SQLite functions") && e.contains("postgresql")), "{errors:?}");
}

#[test]
#[ignore = "requires Spinel, SPINEL_PG_DIR, pg gem and ROUNDHOUSE_PG_READONLY_URL; SELECT only"]
fn native_postgresql_values_and_types_match_the_same_ruby_on_cruby() {
    let url = std::env::var("ROUNDHOUSE_PG_READONLY_URL").expect("explicit read-only PG URL required");
    let pg_dir = std::env::var("SPINEL_PG_DIR").expect("SPINEL_PG_DIR required");
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let (tree, errors) = app().emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let script = r##"# frozen_string_literal: true
require_relative "runtime/sqlite_adapter"
require_relative "runtime/db"
require_relative "runtime/active_support_ext"
require_relative "runtime/active_support_duration"
require_relative "runtime/active_record"
require_relative "app/models"
Db.configure(ENV.fetch("ROUNDHOUSE_PG_READONLY_URL"), pool_size: 2)
ActiveRecord.adapter = SqliteAdapter
2.times do |index|
  connection = Db.pool.conn(index)
  raise "new pool path is writable" unless connection.client.exec("SHOW default_transaction_read_only").getvalue(0, 0) == "on"
  connection.drop
  raise "reopened pool path is writable" unless connection.client.exec("SHOW default_transaction_read_only").getvalue(0, 0) == "on"
end
Db.exec("BEGIN READ ONLY")
query = Widget.from("(VALUES (1, 'O''Reilly?'::text, TRUE, 1.25::float8), (2, 'hidden', FALSE, -2.5::float8), (3, NULL, NULL, 3.5::float8)) AS widgets(id,name,active,score)")
log = Db.capture_sql { query.order(:id).to_a.each { |w| puts "#{w.id}|#{w.name.inspect}|#{w.active.inspect}|#{w.score}" } }
raise "read count" unless log.length == 1
raise "boolean predicate" unless query.where(active: true).to_a.length == 1
raise "NULL predicate" unless query.where(active: nil).to_a.length == 1
# Non-null Float write serialization must be statically well-typed even
# though this read-only test never calls save or emits a write to the DB.
Db.exec("ROLLBACK")
Db.close
"##;
    std::fs::write(tree.join("pg_readonly.rb"), script).unwrap();
    let compiled = Command::new(&compiler)
        .args(["--rbs", ".", "-I", &pg_dir, "pg_readonly.rb", "-o", "pg_readonly"])
        .current_dir(&*tree).output().expect("compile Spinel");
    assert!(compiled.status.success(), "{}", String::from_utf8_lossy(&compiled.stderr));
    let native = Command::new(tree.join("pg_readonly")).current_dir(&*tree)
        .env("ROUNDHOUSE_PG_READONLY_URL", &url).env("DATABASE_READONLY", "1").env("DATABASE_POOL_SIZE", "2").output().expect("run native");
    assert!(native.status.success(), "{}", String::from_utf8_lossy(&native.stderr));
    // Exactly the same emitted Ruby and entry script, only the platform PG
    // connection shim changes from spinel-pg to the gem's keyword API.
    std::fs::write(tree.join("runtime/pg_driver.rb"), std::fs::read("runtime/spinel/pg_driver_cruby.rb").unwrap()).unwrap();
    let compat = Command::new("ruby").args(["--enable-frozen-string-literal", "pg_readonly.rb"])
        .current_dir(&*tree).env("ROUNDHOUSE_PG_READONLY_URL", &url)
        .env("DATABASE_READONLY", "1").env("DATABASE_POOL_SIZE", "2")
        .env("PGOPTIONS", "-c default_transaction_read_only=on -c statement_timeout=15000")
        .output().expect("run compatibility Ruby");
    assert!(compat.status.success(), "{}", String::from_utf8_lossy(&compat.stderr));
    assert_eq!(native.stdout, compat.stdout);
    assert_eq!(String::from_utf8_lossy(&native.stdout), "1|\"O'Reilly?\"|true|1.25\n2|\"hidden\"|false|-2.5\n3|nil|nil|3.5\n");
}

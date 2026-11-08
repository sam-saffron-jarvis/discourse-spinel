//! Real AR lease release conditions, without stealing an outer readonly PG pin.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
use std::process::Command;
fn run(command: &mut Command) -> Vec<u8> {
    let out = command.output().expect("run pool probe");
    assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
        String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    out.stdout
}
#[test]
#[ignore = "requires Spinel, SPINEL_PG_DIR, Rails/pg, strace and ROUNDHOUSE_PG_READONLY_URL; readonly SHOW only"]
fn emitted_pool_completion_matches_rails_and_preserves_fixture_owner() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let url = std::env::var("ROUNDHOUSE_PG_READONLY_URL").expect("explicit readonly URL required");
    let (tree, errors) = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("config/database.yml", "test:\n  adapter: postgresql\n  database: unused\n")
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let matrix = std::fs::read_to_string(root.join("tests/connection_pool_executor_matrix.rb")).unwrap();
    let shared = r#"require_relative "runtime/db"
require_relative "runtime/sqlite_adapter"
require_relative "runtime/base64"
require_relative "runtime/params"
require_relative "runtime/active_support_ext"
require_relative "runtime/rails"
require_relative "runtime/active_record"
raise "readonly policy missing" unless ENV.fetch("DATABASE_READONLY") == "1" && ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
Db.configure(ENV.fetch("ROUNDHOUSE_PG_READONLY_URL"), pool_size: 1)
ActiveRecord.adapter = SqliteAdapter
def begin_fixture
  Db.exec("BEGIN READ ONLY")
  Thread.current[:pool_test_fixture_connection] = Thread.current[:db_conn]
end
def fixture_preserved?
  !Thread.current[:db_conn].nil? && Thread.current[:db_conn].equal?(Thread.current[:pool_test_fixture_connection]) && Db.transaction_open?
end
def end_fixture
  Db.exec("ROLLBACK")
end
"#;
    std::fs::write(tree.join("pool.rb"), format!("{shared}\n{matrix}")).unwrap();
    std::fs::write(tree.join("reference.rb"), format!(r#"require {:?}
RailsOracle.activate("activerecord", pg: ">= 1.5")
require "active_record"
raise "readonly policy missing" unless ENV.fetch("DATABASE_READONLY") == "1" && ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
ActiveRecord::Base.establish_connection(ENV.fetch("ROUNDHOUSE_PG_READONLY_URL"))
def begin_fixture
  connection = ActiveRecord::Base.connection
  connection.execute("BEGIN READ ONLY")
  Thread.current[:pool_test_fixture_connection] = connection.raw_connection
end
def fixture_preserved?
  Thread.current[:pool_test_fixture_connection].transaction_status == PG::PQTRANS_INTRANS
end
def end_fixture
  Thread.current[:pool_test_fixture_connection].exec("ROLLBACK")
end
{matrix}"#, root.join("tests/support/rails_oracle.rb").to_str().unwrap())).unwrap();
    let env = [("ROUNDHOUSE_PG_READONLY_URL", url.as_str()), ("DATABASE_READONLY", "1"),
        ("PGOPTIONS", "-c default_transaction_read_only=on -c statement_timeout=15000")];
    let expected = run(Command::new("timeout").args(["45", "ruby", "--enable-frozen-string-literal", "reference.rb"]).current_dir(&*tree).envs(env));
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let pg = std::env::var("SPINEL_PG_DIR").expect("SPINEL_PG_DIR required");
    run(Command::new(&compiler).args(["--jobs=4", "--rbs", ".", "-I", &pg, "pool.rb", "-o", "pool"]).current_dir(&*tree).envs(env));
    let trace = tree.join("pool.trace");
    let actual = run(Command::new("strace").args(["-f", "-e", "trace=execve,connect", "-o"]).arg(&trace).arg(tree.join("pool")).current_dir(&*tree).envs(env));
    assert_eq!(actual, expected);
    let trace = std::fs::read_to_string(trace).unwrap();
    assert_eq!(trace.matches("execve(").count(), 1);
    assert_eq!(trace.matches("connect(").count(), 1, "{trace}");
    std::fs::copy(root.join("runtime/spinel/pg_driver_cruby.rb"), tree.join("runtime/pg_driver.rb")).unwrap();
    assert_eq!(run(Command::new("timeout").args(["45", "ruby", "--enable-frozen-string-literal", "pool.rb"]).current_dir(&*tree).envs(env)), expected);
}

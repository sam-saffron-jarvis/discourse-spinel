//! Emitted query-cache lifetime vs actual Rails executor hooks/BodyProxy.
//! Explicit readonly PostgreSQL session; SHOW only, no fixture mutation.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
use std::process::Command;

fn run(command: &mut Command) -> Vec<u8> {
    let out = command.output().expect("run query cache scope probe");
    assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
        String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    out.stdout
}

#[test]
#[ignore = "requires Spinel, SPINEL_PG_DIR, Rails/pg gems, strace and ROUNDHOUSE_PG_READONLY_URL; SHOW only"]
fn emitted_scope_owns_cache_until_body_close_and_matches_rails() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let url = std::env::var("ROUNDHOUSE_PG_READONLY_URL").expect("explicit readonly PG URL required");
    let (tree, errors) = emit_and_run::empty_app()
        .write("config/database.yml", "test:\n  adapter: postgresql\n  database: unused\n")
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    assert!(tree.join("runtime/active_record/query_cache_scope.rb").exists());
    assert!(tree.join("runtime/active_record/query_cache_scope.rbs").exists());
    let matrix = std::fs::read_to_string(root.join("tests/query_cache_scope_matrix.rb")).unwrap();
    let shared = r#"require_relative "runtime/db"
require_relative "runtime/active_record/query_cache_scope"
raise "readonly test policy missing" unless ENV.fetch("DATABASE_READONLY") == "1" && ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
Db.configure(ENV.fetch("ROUNDHOUSE_PG_READONLY_URL"), pool_size: 1)
raise "writable connection" unless Db.current_conn.client.exec("SHOW default_transaction_read_only").getvalue(0, 0) == "on"
def cache_enabled?
  Db.query_cache_enabled?
end
def start_scope
  ActiveRecord::QueryCacheScope.new
end
def complete_scope(scope)
  scope.complete!
end
def body_for_scope(scope)
  ActiveRecord::QueryCacheScopeBody.new(["first", "second"], scope)
end
"#;
    std::fs::write(tree.join("scope.rb"), format!("{shared}\n{matrix}")).unwrap();
    let reference = format!(r#"require {:?}
RailsOracle.activate("activerecord", pg: ">= 1.5")
require "active_record"
require "rack/body_proxy"
ActiveRecord::Base.establish_connection(ENV.fetch("ROUNDHOUSE_PG_READONLY_URL"))
def cache_enabled?
  !!ActiveRecord::Base.connection_pool.query_cache_enabled
end
def start_scope
  ActiveRecord::QueryCache::ExecutorHooks.run
end
def complete_scope(scope)
  ActiveRecord::QueryCache::ExecutorHooks.complete(scope)
end
def body_for_scope(scope)
  Rack::BodyProxy.new(["first", "second"]) {{ complete_scope(scope) }}
end
{matrix}"#, root.join("tests/support/rails_oracle.rb").to_str().unwrap());
    std::fs::write(tree.join("reference.rb"), reference).unwrap();
    let expected = run(Command::new("ruby").args(["--enable-frozen-string-literal", "reference.rb"]).current_dir(&*tree).env("ROUNDHOUSE_PG_READONLY_URL", &url).env("DATABASE_READONLY", "1").env("DATABASE_POOL_SIZE", "1").env("PGOPTIONS", "-c default_transaction_read_only=on -c statement_timeout=15000"));
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let pg = std::env::var("SPINEL_PG_DIR").expect("SPINEL_PG_DIR required");
    for mode in ["raise", "promote"] {
        let binary = format!("scope-{mode}");
        run(Command::new(&compiler).args(["--jobs=4", &format!("--int-overflow={mode}"), "--rbs", ".", "-I", &pg, "scope.rb", "-o", &binary]).current_dir(&*tree).env("ROUNDHOUSE_PG_READONLY_URL", &url).env("DATABASE_READONLY", "1").env("DATABASE_POOL_SIZE", "1").env("PGOPTIONS", "-c default_transaction_read_only=on -c statement_timeout=15000"));
        let trace = tree.join(format!("scope-{mode}.trace"));
        let observed = run(Command::new("strace").args(["-f", "-e", "trace=execve,connect", "-o"]).arg(&trace).arg(tree.join(binary)).current_dir(&*tree).env("ROUNDHOUSE_PG_READONLY_URL", &url).env("DATABASE_READONLY", "1").env("DATABASE_POOL_SIZE", "1").env("PGOPTIONS", "-c default_transaction_read_only=on -c statement_timeout=15000"));
        assert_eq!(observed, expected);
        let trace = std::fs::read_to_string(trace).unwrap();
        assert_eq!(trace.matches("execve(").count(), 1);
        assert_eq!(trace.matches("connect(").count(), 1, "{trace}");
    }
    std::fs::copy(root.join("runtime/spinel/pg_driver_cruby.rb"), tree.join("runtime/pg_driver.rb")).unwrap();
    assert_eq!(run(Command::new("ruby").args(["--enable-frozen-string-literal", "scope.rb"]).current_dir(&*tree)
        .env("ROUNDHOUSE_PG_READONLY_URL", &url).env("DATABASE_READONLY", "1").env("DATABASE_POOL_SIZE", "1")
        .env("PGOPTIONS", "-c default_transaction_read_only=on -c statement_timeout=15000")), expected);
    assert_eq!(String::from_utf8_lossy(&expected), "initial:false\nouter:true\ninner-complete:true\nfirstsecond\nbody-materialized-not-closed:true\nouter-complete:false\ndouble-close:false\nold-body-cannot-complete-later-scope:true\nlater-complete:false\nexception-cleanup:false\n");
}

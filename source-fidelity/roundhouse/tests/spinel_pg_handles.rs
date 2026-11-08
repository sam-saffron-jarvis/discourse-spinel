//! Real PostgreSQL handle bookkeeping, without opening a database connection.
//! SPINEL=/path/to/spinel SPINEL_PG_DIR=/path/to/pg cargo test --test spinel_pg_handles -- --ignored --nocapture
use std::path::{Path, PathBuf};
use std::process::Command;

fn run(command: &mut Command) -> Vec<u8> {
    let out = command.output().expect("run PostgreSQL handle probe");
    assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
        String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    out.stdout
}

#[test]
#[ignore = "requires Spinel, SPINEL_PG_DIR and pg gem; no database connection"]
fn typed_free_slots_reuse_and_release_match_cruby_with_integer_promotion() {
    let root = Path::new(env!("CARGO_MANIFEST_DIR"));
    let base = option_env!("CARGO_TARGET_TMPDIR").map(PathBuf::from).unwrap_or_else(std::env::temp_dir);
    let dir = base.join(format!("roundhouse-pg-handles-{}", std::process::id()));
    std::fs::create_dir_all(&dir).unwrap();
    for stem in ["db_pg", "pg_errors", "pg_driver", "active_support_time_parsing", "active_support_interval", "active_support_duration"] {
        for ext in ["rb", "rbs"] {
            let name = format!("{stem}.{ext}");
            std::fs::copy(root.join("runtime/spinel").join(&name), dir.join(name)).unwrap();
        }
    }
    std::fs::copy(root.join("runtime/ruby/db.rbs"), dir.join("db_contract.rbs")).unwrap();
    std::fs::copy(root.join("tests/spinel_pg_handles.rb"), dir.join("probe.rb")).unwrap();
    // Keep the real Integer array seed: weakening it would mask the regression.
    assert!(std::fs::read_to_string(dir.join("db_pg.rbs")).unwrap().contains("@free_slots: Array[Integer]"));
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let pg = std::env::var("SPINEL_PG_DIR").expect("SPINEL_PG_DIR required");
    let expected = b"2\n-1\n0\n1\n0\nhandle reuse, stale handles and repeated release: OK\n";
    for mode in ["raise", "promote"] {
        let binary = format!("probe-{mode}");
        run(Command::new(&compiler).args(["--jobs=4", &format!("--int-overflow={mode}"), "--rbs", ".", "-I", &pg, "probe.rb", "-o", &binary]).current_dir(&dir));
        assert_eq!(run(Command::new(dir.join(binary)).current_dir(&dir)), expected);
    }
    // Only the platform driver changes; the runtime and probe Ruby stay identical.
    std::fs::copy(root.join("runtime/spinel/pg_driver_cruby.rb"), dir.join("pg_driver.rb")).unwrap();
    assert_eq!(run(Command::new("ruby").args(["--enable-frozen-string-literal", "probe.rb"]).current_dir(&dir)), expected);
    std::fs::remove_dir_all(dir).unwrap();
}

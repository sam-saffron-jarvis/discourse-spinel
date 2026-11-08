//! Real synchronous tracker sessions/read-lock completion vs original Rails.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
use std::process::Command;

fn run(command: &mut Command) -> Vec<u8> {
    let out = command.output().expect("run tracker probe");
    assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
        String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    out.stdout
}

#[test]
#[ignore = "requires Spinel and Rails gems; no DB/network needed"]
fn emitted_session_stack_and_waiting_completion_match_rails() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let (tree, errors) = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("app/lib/tracker_probe.rb", "class TrackerProbe\n  def self.session\n    ActiveRecord::AsynchronousQueriesTracker.run.current_session.active?\n  end\nend\n")
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let matrix = std::fs::read_to_string(root.join("tests/asynchronous_queries_tracker_matrix.rb")).unwrap();
    std::fs::write(tree.join("tracker.rb"), format!("require_relative \"runtime/active_record/errors\"\nrequire_relative \"runtime/active_record/asynchronous_queries_tracker\"\n{matrix}")).unwrap();
    std::fs::write(tree.join("reference.rb"), format!(r#"require {:?}
RailsOracle.activate("activerecord")
require "active_record"
{matrix}"#, root.join("tests/support/rails_oracle.rb").to_str().unwrap())).unwrap();
    let expected = run(Command::new("timeout").args(["30", "ruby", "--enable-frozen-string-literal", "reference.rb"]).current_dir(&*tree));
    assert_eq!(run(Command::new("timeout").args(["30", "ruby", "--enable-frozen-string-literal", "tracker.rb"]).current_dir(&*tree)), expected);
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    run(Command::new(&compiler).args(["--jobs=4", "--rbs", ".", "tracker.rb", "-o", "tracker"]).current_dir(&*tree));
    assert_eq!(run(Command::new("timeout").arg("30").arg(tree.join("tracker")).current_dir(&*tree)), expected);
}

#[test]
fn tracker_declares_its_session_stack() {
    let signatures = roundhouse::rbs::parse_app_ivars(include_str!("../runtime/ruby/active_record/asynchronous_queries_tracker.rbs")).unwrap();
    assert!(signatures.keys().any(|id| id.0.as_str() == "ActiveRecord::AsynchronousQueriesTracker"));
}

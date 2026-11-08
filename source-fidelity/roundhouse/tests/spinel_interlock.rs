//! Real interlock ownership and reader/writer exclusion vs Rails.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
use std::process::Command;
fn run(command: &mut Command) -> Vec<u8> {
    let out = command.output().expect("run interlock probe");
    assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
        String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    out.stdout
}
#[test]
#[ignore = "requires Spinel and Rails gems; no DB/network needed"]
fn emitted_running_interlock_really_blocks_unloading_and_matches_rails() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let (tree, errors) = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("app/lib/interlock_probe.rb", "class InterlockProbe\n  def self.observe\n    ActiveSupport::Dependencies.interlock.running_depth\n  end\nend\n")
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let matrix = std::fs::read_to_string(root.join("tests/interlock_matrix.rb")).unwrap();
    std::fs::write(tree.join("interlock.rb"), format!("require_relative \"runtime/active_support_interlock\"\n{matrix}")).unwrap();
    // This standalone caller exercises APIs outside the app's current route set;
    // restore the canonical framework source, whose exact bytes are under test.
    std::fs::copy(root.join("runtime/ruby/active_support_interlock.rb"), tree.join("runtime/active_support_interlock.rb")).unwrap();
    std::fs::write(tree.join("reference.rb"), format!(r#"require {:?}
RailsOracle.activate("activesupport")
require "active_support"
require "active_support/dependencies"
class ActiveSupport::Dependencies::Interlock
  def running_depth
    raw_state {{ |state| state.fetch(Thread.current, {{}}).fetch(:sharing, 0) }}
  end
end
{matrix}"#, root.join("tests/support/rails_oracle.rb").to_str().unwrap())).unwrap();
    let expected = run(Command::new("timeout").args(["30", "ruby", "--enable-frozen-string-literal", "reference.rb"]).current_dir(&*tree));
    assert_eq!(run(Command::new("timeout").args(["30", "ruby", "--enable-frozen-string-literal", "interlock.rb"]).current_dir(&*tree)), expected);
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    run(Command::new(&compiler).args(["--jobs=4", "--rbs", ".", "interlock.rb", "-o", "interlock"]).current_dir(&*tree));
    assert_eq!(run(Command::new("timeout").arg("30").arg(tree.join("interlock")).current_dir(&*tree)), expected);
}

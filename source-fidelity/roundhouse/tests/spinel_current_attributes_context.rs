//! Actual generated CurrentAttributes instances and context frames vs Rails.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
use std::process::Command;

fn run(command: &mut Command) -> Vec<u8> {
    let out = command.output().expect("run context probe");
    assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
        String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
    out.stdout
}

#[test]
#[ignore = "requires Spinel and Rails gems; no DB/network needed"]
fn emitted_generic_registry_and_nested_frames_match_rails() {
    let root = std::path::Path::new(env!("CARGO_MANIFEST_DIR"));
    let current = "class Current < ActiveSupport::CurrentAttributes\n  attribute :value #: String\nend\n";
    let other = current.replace("class Current", "class OtherCurrent");
    let (tree, errors) = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("app/models/current.rb", current)
        .write("app/models/other_current.rb", &other)
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let matrix = std::fs::read_to_string(root.join("tests/current_attributes_context_matrix.rb")).unwrap();
    std::fs::write(tree.join("context.rb"), format!("require_relative \"runtime/active_support_reporters\"\nrequire_relative \"app/models/current\"\nrequire_relative \"app/models/other_current\"\n{matrix}")).unwrap();
    std::fs::write(tree.join("reference.rb"), format!(r#"require {:?}
RailsOracle.activate("activesupport")
require "active_support"
require "active_support/current_attributes"
{current}
{other}
{matrix}"#, root.join("tests/support/rails_oracle.rb").to_str().unwrap())).unwrap();
    let expected = run(Command::new("ruby").args(["--enable-frozen-string-literal", "reference.rb"]).current_dir(&*tree));
    assert_eq!(run(Command::new("ruby").args(["--enable-frozen-string-literal", "context.rb"]).current_dir(&*tree)), expected);
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    run(Command::new(&compiler).args(["--jobs=4", "--rbs", ".", "context.rb", "-o", "context"]).current_dir(&*tree));
    assert_eq!(run(Command::new(tree.join("context")).current_dir(&*tree)), expected);
    assert!(String::from_utf8_lossy(&expected).contains("outer-restored:\"outer\":\"other-outer\":2:{request: \"outer\"}"));
}

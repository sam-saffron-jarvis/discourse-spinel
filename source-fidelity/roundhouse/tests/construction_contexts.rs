#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::construction_contexts::{self, RootSource};
use std::collections::HashMap;
use std::path::PathBuf;
const SOURCE: &str = r#"class GuestRole
  def admin?
    false
  end
end
module VisiblePolicy
  def filter(rows)
    return rows if privileged? && MissingPolicy.flag
    rows.select { |n| n > 1 }
  end
end
class AccessGate
  include VisiblePolicy
  def initialize(user = nil, request = nil)
    @user = user || GuestRole.new
    @request = request
  end
  def privileged?
    @user.admin?
  end
end
class Entry
  def self.run
    AccessGate.new.filter([1, 2, 3])
  end
end
"#;
fn ingest(source: &str) -> roundhouse::App {
    roundhouse::ingest::ingest_app_from_tree(HashMap::from([
        (
            PathBuf::from("config/routes.rb"),
            b"Rails.application.routes.draw do\nend\n".to_vec(),
        ),
        (
            PathBuf::from("db/schema.rb"),
            b"ActiveRecord::Schema.define do\nend\n".to_vec(),
        ),
        (PathBuf::from("lib/gate.rb"), source.as_bytes().to_vec()),
    ]))
    .unwrap()
}
fn root(text: &str) -> Vec<RootSource> {
    vec![RootSource {
        path: "entry.rb".into(),
        text: text.into(),
    }]
}
fn emitted(source: &str, root_text: &str) -> (PathBuf, construction_contexts::Report) {
    let mut app = ingest(source);
    let report = construction_contexts::specialize(&mut app, &root(root_text));
    let diagnostics = roundhouse::session::analyze_and_lower_for(
        &mut app,
        roundhouse::project::BuildTarget::Spinel,
    );
    assert!(
        !diagnostics
            .iter()
            .any(|d| d.severity == roundhouse::diagnostic::Severity::Error),
        "{diagnostics:#?}"
    );
    let dir = std::env::temp_dir().join(format!(
        "rh-construction-context-{}-{}",
        std::process::id(),
        std::time::SystemTime::now()
            .duration_since(std::time::UNIX_EPOCH)
            .unwrap()
            .as_nanos()
    ));
    std::fs::create_dir_all(&dir).unwrap();
    let (files, diagnostics) = roundhouse::emit::diagnostics::scope(|| {
        roundhouse::project::target_files(&app, &dir, roundhouse::project::BuildTarget::Spinel)
            .unwrap()
    });
    assert!(
        !diagnostics
            .iter()
            .any(|d| d.severity == roundhouse::diagnostic::Severity::Error),
        "{diagnostics:#?}"
    );
    for (path, content) in files {
        let target = dir.join(path);
        std::fs::create_dir_all(target.parent().unwrap()).unwrap();
        std::fs::write(target, content).unwrap();
    }
    (dir, report)
}
#[test]
fn pure_false_context_retains_the_original_left_call_and_constructor_body() {
    let (dir, report) = emitted(SOURCE, "p Entry.run\n");
    assert!(report.refusals.is_empty(), "{:?}", report.refusals);
    assert_eq!(report.rewrites.len(), 1);
    assert_eq!(report.contexts.len(), 1);
    let policy = std::fs::read_to_string(dir.join("app/models/visible_policy.rb")).unwrap();
    assert!(policy.contains("return rows if privileged?"), "{policy}");
    assert!(!policy.contains("MissingPolicy"), "{policy}");
    let constructor = std::fs::read_to_string(dir.join("app/models/access_gate.rb")).unwrap();
    assert!(
        constructor.contains("unsupported construction context")
            && constructor.contains("@user = user || GuestRole.new"),
        "{constructor}"
    );
    let original = emit_and_run::ruby()
        .args(["-e", &format!("{SOURCE}\np Entry.run")])
        .output()
        .unwrap();
    let lowered = emit_and_run::ruby().args(["-e","require_relative 'runtime/active_support_ext'; require_relative 'app/models'; p Entry.run"]).current_dir(&dir).output().unwrap();
    assert!(original.status.success());
    assert!(
        lowered.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(original.stdout, lowered.stdout);
    assert!(!report.rewrites[0].witnesses.is_empty());
    let changed = emit_and_run::ruby().args(["-e", "require_relative 'runtime/active_support_ext'; require_relative 'app/models'; class GuestRole; def admin?; true; end; end; begin; Entry.run; raise 'fact guard missing'; rescue RuntimeError => error; raise unless error.message.include?('requires a falsy predicate'); end"]).current_dir(&dir).output().unwrap();
    assert!(
        changed.status.success(),
        "{}",
        String::from_utf8_lossy(&changed.stderr)
    );
    std::fs::remove_dir_all(dir).unwrap();
}
#[test]
fn authenticated_admin_overrides_mutations_and_unknown_worlds_do_not_drop_dependencies() {
    for (label, source, extra) in [
        (
            "admin source override",
            SOURCE.replace("    false", "    true"),
            "p Entry.run",
        ),
        (
            "authenticated input",
            SOURCE.into(),
            "AccessGate.new(Admin.new)",
        ),
        (
            "unknown input",
            SOURCE.into(),
            "AccessGate.new(runtime_user)",
        ),
        (
            "field writer",
            SOURCE.replace(
                "  def privileged?",
                "  def user=(value); @user = value; end\n  def privileged?",
            ),
            "p Entry.run",
        ),
        (
            "reflection",
            SOURCE.into(),
            "AccessGate.new.instance_variable_set(:@user, Admin.new)",
        ),
        (
            "plugin reopen",
            SOURCE.into(),
            "class GuestRole\n def admin?; true; end\nend\np Entry.run",
        ),
        (
            "core override",
            SOURCE.into(),
            "class NilClass; def presence; Other.new; end; end",
        ),
        (
            "indirect shared module",
            format!("{SOURCE}\nmodule IndirectPolicy; include VisiblePolicy; end\n"),
            "p Entry.run",
        ),
        (
            "shared module",
            format!("{SOURCE}\nclass OtherGate\n include VisiblePolicy\nend\n"),
            "p Entry.run",
        ),
        (
            "side effect predicate",
            SOURCE.replace(
                "  def privileged?\n    @user.admin?",
                "  def privileged?\n    observe_call\n    @user.admin?",
            ),
            "p Entry.run",
        ),
    ] {
        let mut app = ingest(&source);
        let report = construction_contexts::specialize(&mut app, &root(extra));
        assert!(
            report.rewrites.is_empty(),
            "{label}: {}",
            serde_json::to_string_pretty(&report).unwrap()
        );
        let policy = app
            .library_classes
            .iter()
            .find(|c| c.name.0.as_str() == "VisiblePolicy")
            .unwrap();
        assert!(
            format!("{:?}", policy.methods[0].body).contains("MissingPolicy"),
            "{label}"
        );
    }
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn native_specialization_keeps_nil_filtering_and_refuses_unseen_constructor_arguments() {
    let (dir, report) = emitted(SOURCE, "p Entry.run");
    assert_eq!(report.rewrites.len(), 1);
    let entry = "require_relative 'runtime/active_support_ext'; require_relative 'app/models'; p Entry.run\nbegin\n AccessGate.new(false)\n raise 'context guard missing'\nrescue RuntimeError => error\n raise unless error.message.include?('unsupported construction context')\n puts 'context guard PASS'\nend\nbegin\n AccessGate.new(nil, false)\n raise 'request guard missing'\nrescue RuntimeError => error\n raise unless error.message.include?('requires nil for request')\n puts 'request guard PASS'\nend\n";
    std::fs::write(dir.join("probe.rb"), entry).unwrap();
    let compiled = std::process::Command::new(std::env::var("SPINEL").unwrap())
        .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
        .current_dir(&dir)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(dir.join("probe"))
        .current_dir(&dir)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(
        native.stdout,
        b"[2, 3]\ncontext guard PASS\nrequest guard PASS\n"
    );
    // Deliberately violate the indexed source world only AFTER specialization:
    // even an unseen override may not silently enter the eliminated dependency.
    std::fs::write(dir.join("probe.rb"), "require_relative 'runtime/active_support_ext'; require_relative 'app/models'; class GuestRole; def admin?; true; end; end; begin; Entry.run; raise 'fact guard missing'; rescue RuntimeError => error; raise unless error.message.include?('requires a falsy predicate'); puts 'fact guard PASS'; end").unwrap();
    let compiled = std::process::Command::new(std::env::var("SPINEL").unwrap())
        .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
        .current_dir(&dir)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(dir.join("probe"))
        .current_dir(&dir)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(native.stdout, b"fact guard PASS\n");
    std::fs::remove_dir_all(dir).unwrap();
}

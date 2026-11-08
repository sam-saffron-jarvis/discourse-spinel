//! Source literals carry allocation semantics, not captured application values.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;

const SOURCE: &str = r#"# frozen_string_literal: true
class SourceLiteralReader
  def self.read
    "source-literal"
  end
  def self.fresh
    +"source-literal"
  end
end
"#;
const DRIVER: &str = r#"raise 'source literal thawed' unless SourceLiteralReader.read.frozen?
raise 'literal interning changed' unless SourceLiteralReader.read.equal?(SourceLiteralReader.read)
raise 'explicit fresh copy frozen' if SourceLiteralReader.fresh.frozen?
raise 'fresh copy identity collapsed' if SourceLiteralReader.fresh.equal?(SourceLiteralReader.fresh)
begin
  SourceLiteralReader.read << 'changed'
  raise 'source frozen mutation accepted'
rescue FrozenError
end
copy = SourceLiteralReader.fresh
copy << 'changed'
raise 'fresh mutation lost' unless copy == 'source-literalchanged'
puts 'source literal allocation PASS'
"#;

fn fixture() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/source_literal_reader.rb", SOURCE)
}

#[test]
fn frozen_source_file_and_explicit_fresh_copy_match_original_ruby() {
    check(false);
}

#[test]
#[ignore = "requires Spinel, no services"]
fn frozen_source_file_and_explicit_fresh_copy_match_natively() {
    check(true);
}

fn check(native: bool) {
    let (emitted, errors) = fixture().emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let control = emit_and_run::ruby()
        .arg("-e")
        .arg(format!("{SOURCE}\n{DRIVER}"))
        .output()
        .unwrap();
    assert!(control.status.success(), "{}", String::from_utf8_lossy(&control.stderr));
    std::fs::write(
        emitted.join("literals.rb"),
        format!("require_relative 'app/models'\n{DRIVER}"),
    )
    .unwrap();
    let ruby = emit_and_run::ruby()
        .arg("literals.rb")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(ruby.status.success(), "{}", String::from_utf8_lossy(&ruby.stderr));
    assert_eq!(ruby.stdout, control.stdout);
    // A source directive does not dispatch an overridable String#freeze.
    // An inline `.freeze` emitter workaround would fail this actual execution.
    let override_source = "class String; def freeze; raise 'synthetic freeze dispatch'; end; end\n";
    let declaration = std::fs::read_to_string(emitted.join("app/models/source_literal_reader.rb")).unwrap();
    let original_override = emit_and_run::ruby()
        .arg("-e")
        .arg(format!("{SOURCE}\n{override_source}{DRIVER}"))
        .output()
        .unwrap();
    let lowered_override = emit_and_run::ruby()
        .arg("-e")
        .arg(format!("{declaration}\n{override_source}{DRIVER}"))
        .output()
        .unwrap();
    assert!(
        original_override.status.success(),
        "{}",
        String::from_utf8_lossy(&original_override.stderr)
    );
    assert!(
        lowered_override.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered_override.stderr)
    );
    assert_eq!(original_override.stdout, lowered_override.stdout);

    if native {
        let compile = std::process::Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
            .args([
                "--load-model=graph",
                "--jobs=4",
                "--rbs",
                ".",
                "literals.rb",
                "-o",
                "literals",
            ])
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(compile.status.success(), "{}", String::from_utf8_lossy(&compile.stderr));
        let output = std::process::Command::new(emitted.join("literals"))
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        assert_eq!(output.stdout, control.stdout);
    }
}

#[test]
fn mixed_source_allocation_is_not_guessed_when_real_reopens_share_a_file() {
    let (_, errors) = fixture()
        .write(
            "lib/source_literal_reopen.rb",
            "class SourceLiteralReader\n  def self.other\n    'mutable-source'\n  end\nend\n",
        )
        .emit(BuildTarget::Ruby);
    assert!(
        errors
            .iter()
            .any(|error| error.contains("mixed source literal allocation")),
        "mixed source domain silently changed: {errors:#?}"
    );
}

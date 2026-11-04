//! The original settings declaration shape computes an interned name with
//! name.to_s.sub("?", "").to_sym and captures a scalar into optional-arg readers.
//! This is pure declaration execution: no PG, Redis, settings snapshots or boot.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const BASE: &str = r##"class DeclarationBase
  def self.declare(name, value)
    clean_name = name.to_s.sub("?", "").to_sym
    define_singleton_method clean_name do |scoped_to = nil|
      value
    end
  end
  def self.capture(name)
    value = name.to_s.sub("?", "")
    clean_name = name.to_s.sub("?", "").to_sym
    define_singleton_method clean_name do
      value
    end
  end
end
class DeclarationValues < DeclarationBase
  declare :disabled?, false
  declare "enabled?", true
  declare "first??", 7
  declare "plain", nil
  capture :mutable?
end
"##;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/declaration_values.rb", source)
}

const PROBE: &str = r#"
raise "false capture" unless DeclarationValues.disabled == false
raise "optional reader" unless DeclarationValues.disabled(:scope) == false
raise "true capture" unless DeclarationValues.enabled == true
raise "only first occurrence" unless DeclarationValues.first? == 7
raise "nil capture" unless DeclarationValues.plain.nil?
DeclarationValues.mutable << "!"
raise "mutable captured allocation" unless DeclarationValues.mutable == "mutable!"
puts "interned declaration captures preserved"
"#;

#[test]
fn interned_sub_names_and_scalar_captures_run_on_emitted_ruby() {
    let run = app(BASE).run_ruby(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "interned declaration captures preserved\n");
}

#[test]
#[ignore = "requires Spinel; SQLite-memory scaffold only"]
fn interned_sub_names_and_scalar_captures_run_natively() {
    let run = app(BASE).run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "interned declaration captures preserved\n");
}

#[test]
fn substitution_on_non_strings_is_not_invented() {
    let source = BASE.replace("name.to_s.sub", "name.sub");
    let (_tree, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.iter().any(|e| e.contains("does not expand") || e.contains("not supported")), "{errors:#?}");
}

#[test]
fn substitution_replacement_backreferences_are_not_guessed() {
    let source = BASE.replace("sub(\"?\", \"\")", "sub(\"?\", \"\\\\&\")");
    let (_tree, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.iter().any(|e| e.contains("does not expand") || e.contains("not supported")), "{errors:#?}");
}

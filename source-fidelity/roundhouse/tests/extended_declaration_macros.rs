//! Source-backed app-module `extend` declarations, without settings boot,
//! cache writes, mutable service state or a production getter substitute.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"module DeclarationMethods
  def declare(name, value)
    clean_name = name.to_s.sub("?", "").to_sym
    define_singleton_method clean_name do |scoped_to = nil|
      value
    end
  end
end
class ExtendedValues
  extend DeclarationMethods
  declare :disabled?, false
  declare "enabled?", true
end
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/extended_values.rb", source)
}

const PROBE: &str = r#"
raise "false capture" unless ExtendedValues.disabled == false
raise "optional argument" unless ExtendedValues.disabled(:scope) == false
raise "true capture" unless ExtendedValues.enabled == true
puts "extended declaration values PASS"
"#;

#[test]
fn extended_declarations_run_on_emitted_ruby() {
    let run = app(SOURCE).run_ruby(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "extended declaration values PASS\n");
}

#[test]
fn extension_effects_order_and_other_uses_remain_refused() {
    let before_extend = SOURCE.replace(
        "  extend DeclarationMethods\n  declare :disabled?, false",
        "  declare :disabled?, false\n  extend DeclarationMethods",
    );
    let hook = SOURCE.replace("module DeclarationMethods\n", "module DeclarationMethods\n  def self.extended(base)\n    raise \"must not discard extension hook\"\n  end\n");
    let constant = SOURCE.replace("module DeclarationMethods\n", "module DeclarationMethods\n  TAG = \"source scope\"\n");
    let another_use = SOURCE.replace("class ExtendedValues\n", "class ExtendedValues\n  def self.declaration_module\n    DeclarationMethods\n  end\n");
    let two_extenders = format!("{SOURCE}\nclass OtherValues\n  extend DeclarationMethods\nend\n");
    let reopened = format!("{SOURCE}\nclass ExtendedValues\nend\n");
    let initial_state = SOURCE.replace("module DeclarationMethods\n", "module DeclarationMethods\n  @before = true\n");
    let class_hook = SOURCE.replace("class ExtendedValues\n", "class ExtendedValues\n  def self.singleton_method_added(name)\n    raise \"source callback must not be omitted\"\n  end\n");
    let unrelated_load_call = SOURCE.replace("class ExtendedValues\n", "class ExtendedValues\n  def self.observe\n    respond_to?(:disabled)\n  end\n  observe\n");
    let core_reopen = format!("class Class\nend\n{SOURCE}");
    for source in [before_extend, hook, constant, another_use, two_extenders, reopened, initial_state, class_hook, unrelated_load_call, core_reopen] {
        let (_tree, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
        assert!(errors.iter().any(|error| error.contains("runtime-defined method not supported") || error.contains("module is not extended until after this call")), "{errors:#?}");
    }
}

#[test]
fn class_load_observations_keep_original_declaration_order() {
    let source = SOURCE.replace("class ExtendedValues\n", "class ExtendedValues\n  @reader_existed = respond_to?(:disabled)\n  def self.reader_existed\n    @reader_existed\n  end\n");
    let run = app(&source).run_ruby("raise \"reader moved before declaration\" unless ExtendedValues.reader_existed == false\n");
    run.assert_passes();
    let (_tree, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.iter().any(|e| e.contains("runtime-defined method not supported")), "{errors:#?}");
}

#[test]
fn mutable_and_runtime_extension_captures_are_not_relocated() {
    for value in ["[]", "\"mutable\"", "\"runtime\".dup"] {
        let source = SOURCE.replace("declare :disabled?, false", &format!("declare :disabled?, {value}"));
        let (_tree, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
        assert!(errors.iter().any(|e| e.contains("captures a mutable or runtime value")), "{errors:#?}");
    }
    let unused_runtime = SOURCE.replace("    clean_name =", "    unused = helper\n    clean_name =")
        .replace("module DeclarationMethods\n", "module DeclarationMethods\n  def helper\n    @runtime_value\n  end\n");
    let (_tree, errors) = app(&unused_runtime).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.iter().any(|e| e.contains("runtime evaluation before its extension is installed")), "{errors:#?}");
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn extended_declarations_run_natively() {
    let run = app(SOURCE).run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "extended declaration values PASS\n");
}

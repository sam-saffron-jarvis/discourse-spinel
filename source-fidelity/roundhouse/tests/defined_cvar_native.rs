//! Native class-variable presence is a runtime flag, not a whole-program
//! approximation. Nil/false assignments count and inherited storage is shared.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;

const SOURCE: &str = r#"class NativeCvarPresence
  BEFORE = defined?(@@value)
  def self.present
    defined?(@@value)
  end
  def self.assign(value)
    @@value = value
  end
end
class NativeCvarChild < NativeCvarPresence
  def self.present
    defined?(@@value)
  end
  def self.assign(value)
    @@value = value
  end
end
class NativeCvarSeparate
  def self.present
    defined?(@@value)
  end
end
class CallbackList
  cattr_accessor :callbacks
  self.callbacks = []
end
class CallbackChild < CallbackList
  cattr_accessor :callbacks
end
class NativeCvarExercise
  def self.run
    raise "future write folded into load" unless NativeCvarPresence::BEFORE.nil?
    raise "future write folded into method" unless NativeCvarPresence.present.nil?
    raise "unassigned inherited" unless NativeCvarChild.present.nil?
    NativeCvarPresence.assign(nil)
    raise "nil not assigned" unless NativeCvarPresence.present == "class variable"
    raise "inherited nil not assigned" unless NativeCvarChild.present == "class variable"
    NativeCvarChild.assign(false)
    raise "false not assigned" unless NativeCvarPresence.present == "class variable"
    raise "unrelated lexical owner" unless NativeCvarSeparate.present.nil?
    raise "nil seed lost" unless CallbackList.callbacks == []
    CallbackList.callbacks << :original
    raise "subclass redefinition wiped parent" unless CallbackChild.callbacks == [:original]
    CallbackChild.callbacks = [:child]
    raise "subclass sharing lost" unless CallbackList.callbacks == [:child]
    puts "native cvar presence PASS"
  end
end
"#;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/native_cvar_presence.rb", source)
}
#[test]
fn native_target_keeps_runtime_flags_and_nil_seed_syntax() {
    let (out, errors) = app(SOURCE).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let callback = std::fs::read_to_string(out.join("app/models/callback_list.rb")).unwrap();
    assert!(callback.contains("defined?(@@callbacks)"), "{callback}");
    let original = emit_and_run::ruby()
        .args([
            "-ractive_support/core_ext/module/attribute_accessors",
            "-e",
            &format!("{SOURCE}\nNativeCvarExercise.run"),
        ])
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let run = app(SOURCE).run_ruby("NativeCvarExercise.run");
    run.assert_passes();
    assert_eq!(run.stdout.as_bytes(), original.stdout);
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn future_assignment_nil_false_inheritance_and_real_cattr_seed_run_natively() {
    let run = app(SOURCE).run_spinel_with_rbs("NativeCvarExercise.run");
    run.assert_passes();
    assert_eq!(run.stdout, "native cvar presence PASS\n");
}
#[test]
fn nonnative_targets_do_not_silently_accept_a_native_presence_protocol() {
    let (_, errors) =
        app("class NativeCvarPresence; def self.present; defined?(@@value); end; end")
            .emit(BuildTarget::Rust);
    assert!(
        errors.iter().any(|e| e.contains("runtime defined? query")),
        "{errors:?}"
    );
}

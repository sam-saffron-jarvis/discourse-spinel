//! Source-defined extension lifecycle callbacks receive the real receiver and
//! extension module at the extend event, before the next class-body statement.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"module ExtensionLifecycle
  def self.extended(receiver)
    receiver.send(:note_extension, self)
  end
end

class ExtensionLifecycleRoot
  @events = [:body_start]

  def self.note_extension(extension)
    @events << extension.name.to_sym
    @received = extension
  end
  private_class_method :note_extension

  extend ExtensionLifecycle
  @observed_after_extend = @events.dup

  def self.report
    [@events, @observed_after_extend, @received, self]
  end
end

module ExtensionLifecycleTarget
  @events = [:body_start]

  def self.note_extension(extension)
    @events << extension.name.to_sym
    @received = extension
  end
  private_class_method :note_extension

  extend ExtensionLifecycle
  @observed_after_extend = @events.dup

  def self.report
    [@events, @observed_after_extend, @received, self]
  end
end
"#;

const PROBE: &str = r#"
root_events, root_after, root_received, root_receiver = ExtensionLifecycleRoot.report
raise "root callback count/order" unless root_events == [:body_start, :ExtensionLifecycle]
raise "root class body did not observe callback" unless root_after == [:body_start, :ExtensionLifecycle]
raise "callback self was not the source module" unless root_received.equal?(ExtensionLifecycle)
raise "callback receiver was not the root class" unless root_receiver.equal?(ExtensionLifecycleRoot)

module_events, module_after, module_received, module_receiver = ExtensionLifecycleTarget.report
raise "module callback count/order" unless module_events == [:body_start, :ExtensionLifecycle]
raise "module body did not observe callback" unless module_after == [:body_start, :ExtensionLifecycle]
raise "module callback self was not the source module" unless module_received.equal?(ExtensionLifecycle)
raise "callback receiver was not the target module" unless module_receiver.equal?(ExtensionLifecycleTarget)
puts "extension lifecycle identity and order PASS"
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/extension_lifecycle_runtime.rb", source)
}

fn original_ruby(source: &str, probe: &str) -> std::process::Output {
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{source}\n{probe}"))
        .output()
        .expect("run original CRuby extension lifecycle control")
}

fn emitted_ruby(source: &str, probe: &str) -> std::process::Output {
    let (emitted, errors) = app(source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/extension_lifecycle_root'\nrequire_relative 'app/models/extension_lifecycle_target'\n{probe}"))
        .current_dir(&*emitted)
        .output()
        .expect("run emitted Ruby extension lifecycle control")
}

#[test]
fn extension_callback_receives_real_receiver_once_before_next_body_statement() {
    let original = original_ruby(SOURCE, PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    assert_eq!(String::from_utf8_lossy(&original.stdout), "extension lifecycle identity and order PASS\n");

    let lowered = emitted_ruby(SOURCE, PROBE);
    assert!(
        lowered.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&lowered.stdout),
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&lowered.stdout), "extension lifecycle identity and order PASS\n");

    // The callback, not a synthetic seed element, supplies an empty trace's
    // element type. Both source controls must still observe the same hook.
    let empty = SOURCE.replace("[:body_start]", "[]");
    let empty_probe = PROBE.replace("[:body_start, :ExtensionLifecycle]", "[:ExtensionLifecycle]");
    let original_empty = original_ruby(&empty, &empty_probe);
    assert!(original_empty.status.success(), "{}", String::from_utf8_lossy(&original_empty.stderr));
    let lowered_empty = emitted_ruby(&empty, &empty_probe);
    assert!(lowered_empty.status.success(), "{}", String::from_utf8_lossy(&lowered_empty.stderr));
    assert_eq!(original_empty.stdout, lowered_empty.stdout);
}

// Model host for the same lifecycle boundary. The actual-ActiveRecord original
// reference is a separate owned experiment; this consumer loads no DB adapter.
const MODEL_MODULE: &str = r#"module BootstrapExtension
  def self.extended(klass)
    klass.send(:note_bootstrap, :extended)
  end
  def bootstrap_events
    @bootstrap_events ||= []
  end
  protected
  def note_bootstrap(event)
    bootstrap_events << event
  end
end
"#;
const MODEL: &str = r#"class BootstrapSetting < ActiveRecord::Base
  extend BootstrapExtension
  @observed = bootstrap_events.dup
  def self.observed
    @observed
  end
end
"#;
const MODEL_PROBE: &str = r#"
raise "model extension callback missing or wrong order" unless BootstrapSetting.observed == [:extended]
raise "model callback ran again" unless BootstrapSetting.bootstrap_events == [:extended]
puts "model extension bootstrap PASS"
"#;

fn model_app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("db/schema.rb", "ActiveRecord::Schema.define do\n  create_table :bootstrap_settings do |t|\n    t.string :name\n  end\nend\n")
        .write("app/models/bootstrap_extension.rb", MODEL_MODULE)
        .write("app/models/bootstrap_setting.rb", MODEL)
}

#[test]
fn model_extension_installs_the_protected_method_before_its_real_hook() {
    let (emitted, errors) = model_app().emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let lowered = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/bootstrap_setting'\n{MODEL_PROBE}"))
        .current_dir(&*emitted).output().expect("run model extension lifecycle");
    assert!(lowered.status.success(), "{}", String::from_utf8_lossy(&lowered.stderr));
    assert_eq!(lowered.stdout, b"model extension bootstrap PASS\n");
}

const CHANGING_SOURCE: &str = r#"module TypeChangingExtension
  def self.extended(receiver)
    receiver.send(:note_extension, self)
  end
end
class LifecycleTypeChange
  @state = :before
  def initialize
    @state = 42
  end
  def self.note_extension(extension)
    @state = nil
  end
  extend TypeChangingExtension
  @seen = @state || :fallback
  def self.report
    @seen
  end
end
"#;
const CHANGING_PROBE: &str = r#"
raise "callback nil write was folded using stale initializer" unless LifecycleTypeChange.report == :fallback
puts "extension callback storage join PASS"
"#;

#[test]
fn callback_writes_preserve_nil_and_exclude_instance_state_in_initializer_types() {
    let original = original_ruby(CHANGING_SOURCE, CHANGING_PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    let (emitted, typed, errors) = app(CHANGING_SOURCE).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    fn check(expr: &roundhouse::expr::Expr, reads: &mut usize) {
        if matches!(&*expr.node, roundhouse::expr::ExprNode::Ivar { name } if name.as_str() == "state") {
            *reads += 1;
            let Some(roundhouse::ty::Ty::Union { variants }) = &expr.ty else { panic!("class storage lost nil: {:?}", expr.ty) };
            assert!(variants.contains(&roundhouse::ty::Ty::Nil), "{variants:?}");
            assert!(variants.contains(&roundhouse::ty::Ty::Sym), "{variants:?}");
            assert!(!variants.contains(&roundhouse::ty::Ty::Int), "instance state leaked: {variants:?}");
        }
        expr.node.for_each_child(&mut |child| check(child, reads));
    }
    let class = typed.library_classes.iter().find(|class| class.name.0.as_str() == "LifecycleTypeChange").expect("typed class");
    let mut reads = 0;
    for initializer in &class.class_ivar_initializers { check(initializer, &mut reads); }
    assert!(reads > 0, "missing initializer class-state read");
    let lowered = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/lifecycle_type_change'\n{CHANGING_PROBE}"))
        .current_dir(&*emitted).output().expect("run nil-changing callback control");
    assert!(lowered.status.success(), "{}", String::from_utf8_lossy(&lowered.stderr));
    assert_eq!(original.stdout, lowered.stdout);
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn extension_lifecycle_runs_natively_with_emitted_rbs() {
    let run = app(SOURCE).run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "extension lifecycle identity and order PASS\n");
    let changed = app(CHANGING_SOURCE).run_spinel_with_rbs(CHANGING_PROBE);
    changed.assert_passes();
    assert_eq!(changed.stdout, "extension callback storage join PASS\n");
    let model = model_app().run_spinel_with_rbs(MODEL_PROBE);
    model.assert_passes();
    assert_eq!(model.stdout, "model extension bootstrap PASS\n");
}

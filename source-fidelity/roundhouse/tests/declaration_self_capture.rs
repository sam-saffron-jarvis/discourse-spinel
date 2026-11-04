//! A declaration-time self capture is the declaring class object, while a
//! generated method's uncaptured self follows its eventual receiver.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"class SelfCaptureRegistry
  def self.declare(name)
    return if respond_to?(name)
    declaring = self
    define_singleton_method(name) { declaring }
    define_singleton_method(:runtime_receiver) { self }
    define_method(:instance_receiver) { self }
  end
  declare(:declaring_owner)
end
class ChildSelfCaptureRegistry < SelfCaptureRegistry
end
"#;
const PROBE: &str = r#"
raise "declaring self was not captured" unless SelfCaptureRegistry.declaring_owner.equal?(SelfCaptureRegistry)
raise "inherited method rebound captured self" unless ChildSelfCaptureRegistry.declaring_owner.equal?(SelfCaptureRegistry)
raise "method self did not follow subclass" unless ChildSelfCaptureRegistry.runtime_receiver.equal?(ChildSelfCaptureRegistry)
instance = SelfCaptureRegistry.new
raise "instance self became a class object" unless instance.instance_receiver.equal?(instance)
puts "declaration self capture PASS"
"#;
fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/self_capture_registry.rb", SOURCE)
}
#[test]
fn declaring_class_capture_and_runtime_self_are_distinct() {
    let original = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{SOURCE}\n{PROBE}")).output().expect("run original class self capture");
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    let (emitted, errors) = app().emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let lowered = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/self_capture_registry'\nrequire_relative 'app/models/child_self_capture_registry'\n{PROBE}"))
        .current_dir(&*emitted).output().expect("run lowered class self capture");
    assert!(lowered.status.success(), "{}", String::from_utf8_lossy(&lowered.stderr));
    assert_eq!(original.stdout, lowered.stdout);
}
#[test]
fn a_constant_added_observer_cannot_be_bypassed_by_self_capture_staging() {
    let source = SOURCE.replace("  def self.declare(name)", "  def self.const_added(name); raise \"must not add synthetic observable constants\"; end\n  def self.declare(name)");
    let (_, errors) = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/self_capture_registry.rb", &source)
        .emit(roundhouse::project::BuildTarget::Spinel);
    assert!(!errors.is_empty(), "constant lifecycle observer was bypassed");
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn declaring_self_capture_runs_natively_with_emitted_rbs() {
    let run = app().run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "declaration self capture PASS\n");
}

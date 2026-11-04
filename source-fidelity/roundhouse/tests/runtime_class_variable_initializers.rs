//! Full original settings dependencies use native @@ storage initialized by
//! constructors. Preserve source order; synthetic mattr/cattr seeds stay separate.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"require "set"
module ModuleClassVariables
  @@registered = Set.new([:module])
  def registered_from_module
    @@registered
  end
end
class ModuleClassVariableConsumer
  extend ModuleClassVariables
end
class RuntimeClassVariables
  @@events = []
  def self.note(value)
    @@events << value
  end
  def self.construct
    note(:construct)
    Set.new([:seed])
  end
  note(:before)
  BEFORE = @@events.length
  @@registered = construct
  AFTER = @@events.length
  note(:after)
  def self.registered
    @@registered
  end
  def self.events
    @@events
  end
end
class SharedClassVariables < RuntimeClassVariables
  def self.replace(value)
    @@registered = value
  end
end
"#;

const PROBE: &str = r#"
raise "source constant before construction" unless RuntimeClassVariables::BEFORE == 1
raise "source constant after construction" unless RuntimeClassVariables::AFTER == 2
raise "constructor order/count" unless RuntimeClassVariables.events == [:before, :construct, :after]
raise "constructor result" unless RuntimeClassVariables.registered.include?(:seed)
raise "class variable alias" unless SharedClassVariables.registered.equal?(RuntimeClassVariables.registered)
SharedClassVariables.registered.add(:child)
raise "class variable inheritance sharing" unless RuntimeClassVariables.registered.include?(:child)
SharedClassVariables.replace(Set.new([:replacement]))
raise "subclass class-variable assignment" unless RuntimeClassVariables.registered.include?(:replacement)
raise "module class variable lexical owner" unless ModuleClassVariableConsumer.registered_from_module.include?(:module)
raise "unrelated class-variable names collided" if ModuleClassVariableConsumer.registered_from_module.include?(:replacement)
raise "initializer reran" unless RuntimeClassVariables.events.length == 3
puts "runtime class-variable initialization PASS"
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/runtime_class_variables.rb", source)
}

#[test]
fn runtime_cvar_initializers_preserve_source_effects_and_shared_storage() {
    let original = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{SOURCE}\n{PROBE}")).output().unwrap();
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    app(SOURCE).run_ruby(PROBE).assert_passes();
}

#[test]
fn source_cvar_with_unpositioned_mattr_default_remains_refused() {
    let source = SOURCE.replace("  @@events = []", "  mattr_accessor :unpositioned, default: 1\n  @@events = []");
    let errors = app(&source).check_errors();
    assert!(errors.iter().any(|error| error.contains("cattr/mattr defaults require source-order initialization")
        || error.contains("unpositioned includes or mattr/cattr installation")), "{errors:#?}");
}

#[test]
fn runtime_cvar_with_unpositioned_include_remains_refused() {
    let source = format!("module Marker\nend\n{}", SOURCE.replace("class RuntimeClassVariables\n", "class RuntimeClassVariables\n  include Marker\n"));
    let errors = app(&source).check_errors();
    assert!(errors.iter().any(|error| error.contains("unpositioned includes or mattr/cattr installation")), "{errors:#?}");
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn runtime_cvar_initialization_executes_natively() {
    app(SOURCE).run_spinel_with_rbs(PROBE).assert_passes();
}

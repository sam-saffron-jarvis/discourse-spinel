//! A declaration-time respond_to? guard is narrow root-class state, not
//! permission to lower arbitrary dynamic method/state behavior.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"class GuardedPluginRegistry
  @@names = []

  def self.register(name, value)
    return if respond_to?(name)
    @@names << name
    define_singleton_method(name) { value }
  end

  def self.preexisting
    :original
  end

  def self.names
    @@names
  end

  register(:reader_one, false)
  register(:reader_one, true)
  register(:reader_two, true)
  register(:preexisting, :wrong)
end
"#;

const PROBE: &str = r#"
raise "false first declaration was lost" unless GuardedPluginRegistry.reader_one == false
raise "second declaration replaced the first" unless GuardedPluginRegistry.reader_one.equal?(false)
raise "second reader missing" unless GuardedPluginRegistry.reader_two == true
raise "preexisting method was replaced" unless GuardedPluginRegistry.preexisting == :original
raise "duplicate or skipped state event" unless GuardedPluginRegistry.names == [:reader_one, :reader_two]
puts "guarded declaration state PASS"
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/guarded_declaration_state.rb", source)
}

fn original_ruby(source: &str, probe: &str) -> std::process::Output {
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{source}\n{probe}"))
        .output()
        .expect("run original Ruby declaration control")
}

#[test]
fn root_class_guard_preserves_method_and_state_order_in_original_and_emitted_ruby() {
    let original = original_ruby(SOURCE, PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    assert_eq!(String::from_utf8_lossy(&original.stdout), "guarded declaration state PASS\n");

    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let lowered = emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!(
            "require_relative 'app/models/guarded_plugin_registry'\n{PROBE}"
        ))
        .current_dir(&*emitted)
        .output()
        .expect("run emitted Ruby declaration control");
    assert!(
        lowered.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&lowered.stdout),
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&lowered.stdout), "guarded declaration state PASS\n");
}

fn constructor_source() -> String {
    format!("require \"set\"\n{}", SOURCE
        .replace("def self.register(name, value)", "def self.register(name, type)")
        .replace("define_singleton_method(name) { value }", "define_singleton_method(name) do\n      instance_variable_get(:\"@#{name}\") || instance_variable_set(:\"@#{name}\", type.new)\n    end\n    define_method(name) { self.class.public_send(name) }")
        .replace("register(:reader_one, false)", "register(:reader_one, Set)")
        .replace("register(:reader_one, true)", "register(:reader_one, Hash)")
        .replace("register(:reader_two, true)", "register(:reader_two, Hash)"))
}

const CONSTRUCTOR_PROBE: &str = r#"
first = GuardedPluginRegistry.reader_one
raise "captured constructor class" unless first.is_a?(Set)
raise "duplicate declaration replaced constructor" if first.is_a?(Hash)
raise "class-side cache identity" unless first.equal?(GuardedPluginRegistry.reader_one)
raise "instance shortcut" unless first.equal?(GuardedPluginRegistry.new.reader_one)
raise "second constructor" unless GuardedPluginRegistry.reader_two.is_a?(Hash)
raise "existing method" unless GuardedPluginRegistry.preexisting == :original
raise "state count/order" unless GuardedPluginRegistry.names == [:reader_one, :reader_two]
puts "guarded constructor capture PASS"
"#;

#[test]
fn guarded_class_constructor_captures_and_instance_shortcuts_run() {
    let source = constructor_source();
    let original = original_ruby(&source, CONSTRUCTOR_PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    app(&source).run_ruby(CONSTRUCTOR_PROBE).assert_passes();
}

#[test]
fn private_source_methods_are_only_present_with_include_private() {
    let source = SOURCE.replace("respond_to?(name)", "respond_to?(name, true)")
        .replace("  def self.names", "  private_class_method :preexisting\n  def self.names");
    let probe = PROBE.replace("GuardedPluginRegistry.preexisting == :original", "GuardedPluginRegistry.send(:preexisting) == :original");
    let original = original_ruby(&source, &probe);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    app(&source).run_ruby(&probe).assert_passes();
}

#[test]
fn an_overridden_reflection_method_is_not_replaced_by_an_ivar_read() {
    let source = constructor_source().replace("  def self.register", "  def self.instance_variable_get(name)\n    :sentinel\n  end\n  def self.register");
    let probe = "raise 'reflection override bypassed' unless GuardedPluginRegistry.reader_one == :sentinel\n";
    let original = original_ruby(&source, probe);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    app(&source).run_ruby(probe).assert_passes();
    let (emitted, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let text = std::fs::read_to_string(emitted.join("app/models/guarded_plugin_registry.rb")).unwrap();
    assert!(text.contains("instance_variable_get(:@reader_one)"), "{text}");
}

#[test]
fn unproved_dynamic_guards_and_stateful_contexts_remain_refused() {
    let outside_class_load = SOURCE.replace(
        "  @@names = []\n",
        "  @@names = []\n  @observed = respond_to?(:reader_one)\n",
    );
    let custom_respond_to = SOURCE.replace(
        "  def self.register(name, value)\n",
        "  def self.respond_to?(name, include_private = false)\n    false\n  end\n\n  def self.register(name, value)\n",
    );
    let custom_respond_to_missing = SOURCE.replace(
        "  def self.register(name, value)\n",
        "  def self.respond_to_missing?(name, include_private = false)\n    true\n  end\n\n  def self.register(name, value)\n",
    );
    let stateful_factory_callback = SOURCE.replace(
        "  def self.register(name, value)\n",
        "  def self.singleton_method_added(name)\n    @@names << name if name == :reader_one\n  end\n\n  def self.register(name, value)\n",
    );
    let inherited_root = SOURCE.replace(
        "class GuardedPluginRegistry\n",
        "class GuardedPluginRegistry < Object\n",
    );
    let reopen_class = format!("class Class\nend\n{SOURCE}");
    let reopen_object = format!("class Object\nend\n{SOURCE}");
    let reopen_module = format!("class Module\nend\n{SOURCE}");
    let opaque_argument = SOURCE.replace("register(:reader_one, false)", "register(:reader_one, observer)")
        .replace("  def self.register", "  def self.observer\n    respond_to?(:reader_one)\n  end\n  def self.register");
    let opaque_local = SOURCE.replace("    @@names << name", "    value = observer\n    @@names << name")
        .replace("  def self.register", "  def self.observer\n    respond_to?(:reader_one)\n  end\n  def self.register");
    let opaque_state_event = SOURCE.replace("    @@names << name", "    @@names.tap { respond_to?(:reader_one) }");
    let uncertain_core = SOURCE.replace("register(:reader_one, false)", "register(:new, false)");
    let uncertain_framework = SOURCE.replace("register(:reader_one, false)", "register(:delegate, false)");
    let composite_array = SOURCE.replace("register(:reader_one, false)", "register(:reader_one, [])");
    let composite_hash = SOURCE.replace("register(:reader_one, false)", "register(:reader_one, {})");
    let composite_state_alias = SOURCE.replace("register(:reader_one, false)", "register(:reader_one, [])")
        .replace("    @@names << name", "    @@names << value\n    @@names << value")
        .replace("define_singleton_method(name) { value }", "define_singleton_method(name) { false }");

    for (case, source) in [
        ("outside class-load observation", outside_class_load),
        ("custom respond_to?", custom_respond_to),
        ("custom respond_to_missing?", custom_respond_to_missing),
        ("singleton_method_added callback", stateful_factory_callback),
        ("inherited root class", inherited_root),
        ("Class reopen", reopen_class),
        ("Object reopen", reopen_object),
        ("Module reopen", reopen_module),
        ("opaque bootstrap argument", opaque_argument),
        ("opaque bootstrap local", opaque_local),
        ("opaque state callback", opaque_state_event),
        ("uncertain builtin method", uncertain_core),
        ("uncertain framework method", uncertain_framework),
        ("unshared literal Array capture", composite_array),
        ("unshared literal Hash capture", composite_hash),
        ("unshared state container alias", composite_state_alias),
    ] {
        let (_, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
        assert!(
            !errors.is_empty(),
            "unproved {case} unexpectedly emitted without errors"
        );
    }
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn root_class_guard_runs_natively_with_emitted_rbs() {
    let run = app(SOURCE).run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "guarded declaration state PASS\n");
    let constructor = app(&constructor_source()).run_spinel_with_rbs(CONSTRUCTOR_PROBE);
    constructor.assert_passes();
    assert_eq!(constructor.stdout, "guarded constructor capture PASS\n");
}

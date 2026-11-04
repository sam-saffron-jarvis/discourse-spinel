//! Literal blocks passed through a guarded root-class factory must retain
//! Ruby's current-frame block semantics and execute only declaration effects.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r##"class FilteredEntriesRegistry
  @@events = []

  def self.register(name)
    return if respond_to?(name)
    @@events << name
    define_singleton_method(name) do
      instance_variable_get(:"@#{name}") || instance_variable_set(:"@#{name}", [-1, 2, 3])
    end
    define_method(name) { self.class.public_send(name) }
    yield(self) if block_given?
  end

  def self.filtered(name)
    return if respond_to?(name)
    register(name)
    singleton_class.alias_method(:"_raw_#{name}", name)
    define_singleton_method(name) { public_send(:"_raw_#{name}").select { |v| v > 0 } }
    yield(self) if block_given?
  end

  def self.events
    @@events
  end

  filtered(:entries) do |singleton|
    singleton.define_singleton_method("lookup") { public_send(:_raw_entries) }
    singleton.define_singleton_method("owner_class") { singleton }
  end

  filtered(:entries) do |singleton|
    singleton.define_singleton_method("alternate_lookup") { :wrong }
  end
end

class ChildFilteredEntriesRegistry < FilteredEntriesRegistry
end
"##;

const PROBE: &str = r#"
raw = FilteredEntriesRegistry._raw_entries
raise "filtered values" unless FilteredEntriesRegistry.entries == [2, 3]
raise "lookup callback not installed on yielded singleton" unless FilteredEntriesRegistry.respond_to?(:lookup)
raise "lookup does not return cached raw value" unless FilteredEntriesRegistry.lookup.equal?(raw)
raise "raw cache identity changed" unless raw.equal?(FilteredEntriesRegistry._raw_entries)
raw << 4
raise "filtered method lost raw-cache mutation" unless FilteredEntriesRegistry.entries == [2, 3, 4]
raise "instance shortcut" unless FilteredEntriesRegistry.new.entries == [2, 3, 4]
raise "duplicate registration or callback ran" unless FilteredEntriesRegistry.events == [:entries]
raise "duplicate callback installed an alternate method" if FilteredEntriesRegistry.respond_to?(:alternate_lookup)
raise "owner_class was not bound to the declaring root" unless ChildFilteredEntriesRegistry.owner_class.equal?(FilteredEntriesRegistry)
child_raw = ChildFilteredEntriesRegistry._raw_entries
raise "inherited getter did not rebind self" if child_raw.equal?(raw)
child_raw << 5
raise "subclass getter did not use subclass state" unless ChildFilteredEntriesRegistry.entries == [2, 3, 5]
raise "subclass mutation changed root cache" unless FilteredEntriesRegistry.entries == [2, 3, 4]
puts "literal declaration callback PASS"
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/filtered_entries_registry.rb", source)
}

fn original_ruby(source: &str, probe: &str) -> std::process::Output {
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{source}\n{probe}"))
        .output()
        .expect("run original CRuby control")
}

fn emitted_ruby(source: &str, probe: &str) -> std::process::Output {
    let (emitted, errors) = app(source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/filtered_entries_registry'\nrequire_relative 'app/models/child_filtered_entries_registry'\n{probe}"))
        .current_dir(&*emitted)
        .output()
        .expect("run emitted Ruby control")
}

#[test]
fn literal_callback_keeps_current_block_frame_and_installs_once() {
    let original = original_ruby(SOURCE, PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    assert_eq!(String::from_utf8_lossy(&original.stdout), "literal declaration callback PASS\n");

    let lowered = emitted_ruby(SOURCE, PROBE);
    assert!(
        lowered.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&lowered.stdout),
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&lowered.stdout), "literal declaration callback PASS\n");
}

#[test]
fn callback_side_effects_and_unproved_block_shapes_remain_refused() {
    // These sources are emitted only; callback I/O is never executed.
    let io_effect = SOURCE.replace(
        "    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
        "    File.write(\"should_not_run\", \"called\")\n    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
    );
    let opaque_effect = SOURCE.replace(
        "    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
        "    perform_unknown_callback_effect(singleton)\n    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
    );
    let return_in_callback = SOURCE.replace(
        "    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
        "    return :not_a_declaration\n    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
    );
    let break_in_callback = SOURCE.replace(
        "    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
        "    break\n    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
    );
    let non_declaration_callback = SOURCE.replace(
        "    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
        "    singleton.instance_variable_set(:@observed, true)\n    singleton.define_singleton_method(\"lookup\") { public_send(:_raw_entries) }",
    );
    let wrong_yield_arity = SOURCE.replace(
        "filtered(:entries) do |singleton|",
        "filtered(:entries) do |singleton, extra|",
    );
    let wrong_yield_arguments = SOURCE.replace("yield(self)", "yield(self, self)");
    let splatted_yield = SOURCE.replace("yield(self)", "yield(*self)");
    let block_locals = SOURCE.replace("do |singleton|", "do |singleton; local|");
    let destructured_callback = SOURCE.replace("do |singleton|", "do |(singleton)|");
    let optional_callback = SOURCE.replace("do |singleton|", "do |singleton = nil|");
    let unsupported_block_params = SOURCE.replace(
        "filtered(:entries) do |singleton|",
        "filtered(:entries) do |*singleton|",
    );
    let custom_block_given = SOURCE.replace(
        "  def self.register(name)\n",
        "  def self.block_given?; false; end\n\n  def self.register(name)\n",
    );
    let custom_singleton_context = SOURCE.replace(
        "  def self.filtered(name)\n",
        "  def self.singleton_class; self; end\n\n  def self.filtered(name)\n",
    );
    let lifecycle_callback = SOURCE.replace(
        "  def self.register(name)\n",
        "  def self.singleton_method_added(name)\n    @@events << name\n  end\n\n  def self.register(name)\n",
    );

    for (case, source) in [
        ("callback I/O", io_effect),
        ("opaque callback effect", opaque_effect),
        ("return in callback", return_in_callback),
        ("break in callback", break_in_callback),
        ("non-declaration callback statement", non_declaration_callback),
        ("wrong callback arity", wrong_yield_arity),
        ("wrong yield argument count", wrong_yield_arguments),
        ("splatted yield arguments", splatted_yield),
        ("block-local declaration", block_locals),
        ("destructured callback parameter", destructured_callback),
        ("optional callback parameter", optional_callback),
        ("unsupported block parameters", unsupported_block_params),
        ("custom block_given?", custom_block_given),
        ("custom singleton context", custom_singleton_context),
        ("singleton lifecycle callback", lifecycle_callback),
    ] {
        let (_, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
        assert!(!errors.is_empty(), "unproved {case} unexpectedly emitted without errors");
    }
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn literal_declaration_callbacks_run_natively_with_emitted_rbs() {
    let run = app(SOURCE).run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "literal declaration callback PASS\n");
}

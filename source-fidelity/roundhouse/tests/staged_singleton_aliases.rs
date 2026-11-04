//! Singleton aliases created inside guarded root-class declaration runs are
//! snapshots of the old method body, not forwarding calls to the new name.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const FILTERED_SOURCE: &str = r##"class GuardedFilteredRegistry
  @@events = []

  def self.register(name)
    return if respond_to?(name)
    @@events << name
    define_singleton_method(name) do
      instance_variable_get(:"@#{name}") || instance_variable_set(:"@#{name}", [-1, 2, 3])
    end
    define_method(name) { self.class.public_send(name) }
  end

  def self.filtered(name)
    return if respond_to?(name)
    register(name)
    singleton_class.alias_method(:"_raw_#{name}", name)
    define_singleton_method(name) { public_send(:"_raw_#{name}").select { |v| v > 0 } }
  end

  def self.events
    @@events
  end

  filtered(:entries)
  filtered(:entries)
end
"##;

const FILTERED_PROBE: &str = r#"
raw = GuardedFilteredRegistry._raw_entries
raise "raw method initial value" unless raw == [-1, 2, 3]
raise "raw alias did not retain cached object" unless raw.equal?(GuardedFilteredRegistry._raw_entries)
raise "filtered method did not use the raw alias" unless GuardedFilteredRegistry.entries == [2, 3]
raw << 4
raise "filtered method lost mutation through raw alias" unless GuardedFilteredRegistry.entries == [2, 3, 4]
raise "instance shortcut did not call filtered class method" unless GuardedFilteredRegistry.new.entries == [2, 3, 4]
raise "duplicate filtered declaration was not skipped" unless GuardedFilteredRegistry.events == [:entries]
puts "guarded singleton alias state PASS"
"#;

const SNAPSHOT_SOURCE: &str = r#"class SingletonAliasSnapshot
  def self.declare(name)
    return if respond_to?(name)
    define_singleton_method(name) { [__method__, __callee__] }
    singleton_class.alias_method(:raw, name)
    define_singleton_method(name) { :replacement }
  end

  declare(:value)
end
"#;

const SNAPSHOT_PROBE: &str = r#"
raise "current method was not overridden" unless SingletonAliasSnapshot.value == :replacement
raise "raw alias forwarded instead of preserving its snapshot" unless SingletonAliasSnapshot.raw == [:value, :raw]
puts "singleton alias snapshot PASS"
"#;

fn app(path: &str, source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write(path, source)
}

fn original_ruby(source: &str, probe: &str) -> std::process::Output {
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{source}\n{probe}"))
        .output()
        .expect("run original CRuby control")
}

fn emitted_ruby(path: &str, source: &str, emitted_file: &str, probe: &str) -> std::process::Output {
    let (emitted, errors) = app(path, source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/{emitted_file}'\n{probe}"))
        .current_dir(&*emitted)
        .output()
        .expect("run emitted Ruby control")
}

#[test]
fn guarded_filtered_alias_retains_cached_state_and_instance_shortcut() {
    let original = original_ruby(FILTERED_SOURCE, FILTERED_PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    assert_eq!(String::from_utf8_lossy(&original.stdout), "guarded singleton alias state PASS\n");

    let lowered = emitted_ruby(
        "lib/guarded_filtered_registry.rb",
        FILTERED_SOURCE,
        "guarded_filtered_registry",
        FILTERED_PROBE,
    );
    assert!(
        lowered.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&lowered.stdout),
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&lowered.stdout), "guarded singleton alias state PASS\n");
}

#[test]
fn singleton_aliases_snapshot_the_original_method_identity() {
    let original = original_ruby(SNAPSHOT_SOURCE, SNAPSHOT_PROBE);
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    assert_eq!(String::from_utf8_lossy(&original.stdout), "singleton alias snapshot PASS\n");

    let lowered = emitted_ruby(
        "lib/singleton_alias_snapshot.rb",
        SNAPSHOT_SOURCE,
        "singleton_alias_snapshot",
        SNAPSHOT_PROBE,
    );
    assert!(
        lowered.status.success(),
        "{}\n{}",
        String::from_utf8_lossy(&lowered.stdout),
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(String::from_utf8_lossy(&lowered.stdout), "singleton alias snapshot PASS\n");
}

#[test]
fn aliasing_outside_the_proved_guarded_run_remains_refused() {
    let missing_alias = FILTERED_SOURCE.replace(
        "    singleton_class.alias_method(:\"_raw_#{name}\", name)\n",
        "",
    );
    let preexisting_alias = FILTERED_SOURCE
        .replace("class GuardedFilteredRegistry\n", "class GuardedFilteredRegistry\n  def self.preexisting; :original; end\n")
        .replace("singleton_class.alias_method(:\"_raw_#{name}\", name)", "singleton_class.alias_method(:\"_raw_#{name}\", :preexisting)");
    let undefined_source = FILTERED_SOURCE.replace(
        "singleton_class.alias_method(:\"_raw_#{name}\", name)",
        "singleton_class.alias_method(:\"_raw_#{name}\", :not_defined)",
    );
    let custom_singleton_class = FILTERED_SOURCE.replace(
        "  def self.filtered(name)\n",
        "  def self.singleton_class; self; end\n\n  def self.filtered(name)\n",
    );
    let lifecycle_callback = FILTERED_SOURCE.replace(
        "  def self.register(name)\n",
        "  def self.singleton_method_added(name)\n    @@events << name\n  end\n\n  def self.register(name)\n",
    );
    let unknown_runtime_name = FILTERED_SOURCE
        .replace(
            "  filtered(:entries)\n  filtered(:entries)\n",
            "  @runtime_name = :entries\n  def self.runtime_name\n    @runtime_name\n  end\n  filtered(runtime_name)\n",
        );
    let reopen_class = format!("class Class\nend\n{FILTERED_SOURCE}");
    let reopen_object = format!("class Object\nend\n{FILTERED_SOURCE}");
    let reopen_module = format!("class Module\nend\n{FILTERED_SOURCE}");
    let no_replacement = FILTERED_SOURCE.replace("    define_singleton_method(name) { public_send(:\"_raw_#{name}\").select { |v| v > 0 } }\n", "");
    let second_alias = FILTERED_SOURCE.replace("    singleton_class.alias_method(:\"_raw_#{name}\", name)\n",
        "    singleton_class.alias_method(:\"_raw_#{name}\", name)\n    singleton_class.alias_method(:\"_other_#{name}\", name)\n");
    let alias_chain = FILTERED_SOURCE.replace("    singleton_class.alias_method(:\"_raw_#{name}\", name)\n",
        "    singleton_class.alias_method(:\"_raw_#{name}\", name)\n    singleton_class.alias_method(:\"_other_#{name}\", :\"_raw_#{name}\")\n");
    let runtime_helper_edge = format!("{FILTERED_SOURCE}\nclass RuntimeFactoryCaller\n  def self.call\n    GuardedFilteredRegistry.register(:runtime_name)\n  end\nend\n");

    for (case, source) in [
        ("missing alias snapshot before replacement", missing_alias),
        ("undefined alias source", undefined_source),
        ("preexisting alias outside the guarded run", preexisting_alias),
        ("custom singleton_class", custom_singleton_class),
        ("singleton lifecycle callback", lifecycle_callback),
        ("unknown runtime name", unknown_runtime_name),
        ("Class reopen", reopen_class),
        ("Object reopen", reopen_object),
        ("Module reopen", reopen_module),
        ("alias without same-run replacement", no_replacement),
        ("two aliases of one version", second_alias),
        ("alias chain", alias_chain),
        ("remaining runtime helper edge", runtime_helper_edge),
    ] {
        let (_, errors) = app("lib/guarded_filtered_registry.rb", &source)
            .emit(roundhouse::project::BuildTarget::Spinel);
        assert!(!errors.is_empty(), "unproved {case} unexpectedly emitted without errors");
    }
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn guarded_singleton_aliases_run_natively_with_emitted_rbs() {
    let filtered = app("lib/guarded_filtered_registry.rb", FILTERED_SOURCE)
        .run_spinel_with_rbs(FILTERED_PROBE);
    filtered.assert_passes();
    assert_eq!(filtered.stdout, "guarded singleton alias state PASS\n");

    let snapshot = app("lib/singleton_alias_snapshot.rb", SNAPSHOT_SOURCE)
        .run_spinel_with_rbs(SNAPSHOT_PROBE);
    snapshot.assert_passes();
    assert_eq!(snapshot.stdout, "singleton alias snapshot PASS\n");
}

//! Open runtime names are values, not an eagerly emitted literal method set.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
const SOURCE: &str = r#"class OpenDefinitionOwner
  @events = []
  #: () -> Array[Symbol]
  def self.events
    @events
  end
  #: (Symbol name, Integer value) -> Symbol
  def self.install(name, value)
    define_singleton_method(name) { value }
  end
  #: (String input) -> nil
  def self.exercise(input)
    key = input.to_sym
    raise "present before installation" if respond_to?(key, true)
    before_events = events.dup
    raise "install result" unless install(key, 17) == key
    raise "runtime name value" unless public_send(key) == 17
    before = method(key)
    singleton_class.alias_method(:raw, key)
    old = method(:raw)
    raise "alias identity" unless before == old
    raise "alias value" unless old.call == 17
    install(key, 29)
    raise "captured old entry" unless before.call == 17 && old.call == 17
    raise "new entry" unless public_send(key) == 29
    raise "new identity" if method(key) == before
    private_class_method(key)
    raise "private presence" if respond_to?(key)
    raise "private bound call" unless method(key).call == 29
    begin
      public_send(key)
      raise "private public_send"
    rescue NoMethodError
    end
    public_class_method(key)
    raise "callback events" unless events == before_events + [key, :raw, key]
    puts "open runtime name PASS"
    nil
  end
  #: (Symbol name) -> Array[Symbol]
  def self.singleton_method_added(name)
    events << name
  end
  private_class_method :singleton_method_added
end
"#;
fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/open_definition_owner.rb", SOURCE)
}
#[test]
fn arbitrary_runtime_names_match_original_and_lowered() {
    let (emitted, typed, errors) = app().emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    assert_eq!(typed.runtime_definition_families.len(), 1);
    assert!(typed.runtime_definition_families[0].open_names);
    for input in ["runtime_value_071", "other_runtime_592"] {
        let original = emit_and_run::ruby()
            .args(["--enable-frozen-string-literal", "-e"])
            .arg(format!(
                "{SOURCE}\nOpenDefinitionOwner.exercise(ARGV.fetch(0))"
            ))
            .arg(input)
            .output()
            .unwrap();
        assert!(
            original.status.success(),
            "{}",
            String::from_utf8_lossy(&original.stderr)
        );
        let lowered = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
            .arg("require_relative 'app/models/open_definition_owner'\nOpenDefinitionOwner.exercise(ARGV.fetch(0))")
            .arg(input).current_dir(&*emitted).output().unwrap();
        assert!(
            lowered.status.success(),
            "{}",
            String::from_utf8_lossy(&lowered.stderr)
        );
        assert_eq!(lowered.stdout, original.stdout);
    }
    let refused = emit_and_run::ruby().args(["-e", "require_relative 'app/models/open_definition_owner'\nbegin\nOpenDefinitionOwner.install(:object_id, 17)\nraise 'native replacement accepted'\nrescue NotImplementedError\nputs 'native replacement refused'\nend"])
        .current_dir(&*emitted).output().unwrap();
    assert!(
        refused.status.success(),
        "{}",
        String::from_utf8_lossy(&refused.stderr)
    );
    assert_eq!(refused.stdout, b"native replacement refused\n");
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn arbitrary_names_run_natively_without_name_literals() {
    let (emitted, errors) = app().emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(emitted.join("open_name.rb"), "require_relative 'app/models/open_definition_owner'\nif ARGV.length > 1\n  begin\n    OpenDefinitionOwner.install(:object_id, 17)\n    raise 'native replacement accepted'\n  rescue NotImplementedError\n    puts 'native replacement refused'\n  end\nelse\n  OpenDefinitionOwner.exercise(ARGV.fetch(0))\nend\n").unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compiled = std::process::Command::new(compiler)
        .args(["--rbs", ".", "open_name.rb", "-o", "open_name"])
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    for input in ["runtime_value_071", "other_runtime_592"] {
        let native = std::process::Command::new(emitted.join("open_name"))
            .arg(input)
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(
            native.status.success(),
            "{}",
            String::from_utf8_lossy(&native.stderr)
        );
        assert_eq!(native.stdout, b"open runtime name PASS\n");
    }
    let refused = std::process::Command::new(emitted.join("open_name"))
        .args(["ignored", "refuse"])
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        refused.status.success(),
        "{}",
        String::from_utf8_lossy(&refused.stderr)
    );
    assert_eq!(refused.stdout, b"native replacement refused\n");
}

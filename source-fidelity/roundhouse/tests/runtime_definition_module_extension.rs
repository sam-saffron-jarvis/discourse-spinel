//! Reduced from SiteSetting's extend -> SSE.extended -> setup_methods path.
//! Keep the real module and actual class-load extend/callback event; definitions
//! stay runtime events, with class-owner storage distinct from module state.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"module RuntimeSettingExtension
  @values = 701
  #: () -> Integer
  def self.module_value
    @values
  end
  #: (singleton(ExtendedSettingOwner) base) -> nil
  def self.extended(base)
    base.note("extended-enter")
    raise "method installed before callback" if base.respond_to?(:hook_value)
    base.send(:setup_methods, :hook_value, 5)
    raise "callback getter missing" unless base.public_send(:hook_value) == 22
    base.note("extended-leave")
    nil
  end
  #: (Symbol name, Integer delta) -> Symbol
  def setup_methods(name, delta)
    declaring = self
    define_singleton_method(name) do
      raise "factory self moved to module" unless declaring == ExtendedSettingOwner
      @values[name] + delta
    end
  end
end
class ExtendedSettingOwner
  @events = ["discarded-initial-event"]
  @values = {hook_value: 17, from_body: 29, runtime_choice: 31}
  @before_extension = respond_to?(:setup_methods, true)
  #: () -> Array[String]
  def self.events
    @events
  end
  #: (String event) -> Array[String]
  def self.note(event)
    @events << event
  end
  #: () -> bool
  def self.before_extension
    @before_extension
  end
  #: (Hash[Symbol, Integer] values) -> Hash[Symbol, Integer]
  def self.seed(values)
    @values = values
  end
  #: (Symbol name) -> Array[String]
  def self.singleton_method_added(name)
    @events << "added:" + name.to_s
  end
  private_class_method :singleton_method_added
  def self.check_before_extension
    begin
      setup_methods(:early, 1)
      raise "producer called before its extension"
    rescue NoMethodError
      nil
    end
  end
  check_before_extension
  @events.clear
  note("before-extend")
  extend RuntimeSettingExtension
  note("after-extend")
  setup_methods(:from_body, 7)
  note("after-body")
  #: (String input) -> nil
  def self.exercise(input)
    key = input.to_sym
    raise "early module API presence" if before_extension
    raise "module API missing" unless respond_to?(:setup_methods, true)
    raise "wrong class-load events #{events.inspect}" unless events.first(7) == ["before-extend", "extended-enter", "added:hook_value", "extended-leave", "after-extend", "added:from_body", "after-body"]
    raise "body declaration" unless public_send(:from_body) == 36
    setup_methods(key, 11)
    raise "runtime declaration" unless public_send(key) == 42
    ChildExtendedSettingOwner.seed({hook_value: 43, from_body: 47, runtime_choice: 53})
    raise "bound receiver storage" unless ChildExtendedSettingOwner.public_send(key) == 64
    raise "parent storage was changed" unless public_send(key) == 42
    raise "module storage changed" unless RuntimeSettingExtension.module_value == 701
    puts "module extension runtime family PASS"
    nil
  end
end
class ChildExtendedSettingOwner < ExtendedSettingOwner
end
"#;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/extended_setting_owner.rb", source)
}
#[test]
fn real_extension_callback_and_class_load_definitions_match_original() {
    assert_original_and_lowered(SOURCE);
}

fn assert_original_and_lowered(source: &str) {
    let original = emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!(
            "{source}\nExtendedSettingOwner.exercise(ARGV.fetch(0))"
        ))
        .arg("runtime_choice")
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let (emitted, typed, errors) =
        app(source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    fn closed(expr: &roundhouse::expr::Expr) {
        assert!(
            expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
            "{expr:#?}"
        );
        expr.node.for_each_child(&mut closed);
    }
    for class in &typed.library_classes {
        if class.name.0.as_str() == "RuntimeSettingExtension"
            || class.name.0.as_str().starts_with("RoundhouseRuntimeFamily")
        {
            for method in &class.methods {
                closed(&method.body);
            }
        }
    }
    assert!(errors.is_empty(), "{errors:#?}");
    assert_eq!(typed.runtime_definition_families.len(), 1);
    assert_eq!(typed.runtime_extension_events.len(), 1);
    let event = &typed.runtime_extension_events[0];
    assert_eq!(event.module.0.as_str(), "RuntimeSettingExtension");
    assert_eq!(event.owner.0.as_str(), "ExtendedSettingOwner");
    assert!(
        matches!(&*event.original.node, roundhouse::expr::ExprNode::Send { method, .. } if method.as_str() == "extend")
    );
    let json = serde_json::to_string(&typed.runtime_extension_events).unwrap();
    let decoded: Vec<roundhouse::app::RuntimeExtensionEvent> = serde_json::from_str(&json).unwrap();
    assert_eq!(decoded, typed.runtime_extension_events);

    let lowered = emit_and_run::ruby()
        .args([
            "--enable-frozen-string-literal",
            "-e",
            "require_relative 'app/models'; ExtendedSettingOwner.exercise(ARGV.fetch(0))",
        ])
        .arg("runtime_choice")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        lowered.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(lowered.stdout, original.stdout);
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn real_extension_callback_and_class_load_definitions_run_natively() {
    let source = SOURCE
        .replace("  #: (Symbol name, Integer delta) -> Symbol\n", "")
        .replace("  #: (singleton(ExtendedSettingOwner) base) -> nil\n", "");
    let source = with_per_site_reader_storage(&source);
    let (emitted, errors) = app(&source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("extension.rb"),
        "require_relative 'app/models'; ExtendedSettingOwner.exercise(ARGV.fetch(0))\n",
    )
    .unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compiled = std::process::Command::new(compiler)
        .args(["--jobs=4", "--rbs", ".", "extension.rb", "-o", "extension"])
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(emitted.join("extension"))
        .arg("runtime_choice")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(native.stdout, b"module extension runtime family PASS\n");
}

#[test]
fn unsupported_extension_boundaries_keep_the_original_factory_refusal() {
    let cases = [
        (
            "two extenders",
            format!("{SOURCE}\nclass OtherOwner\n  extend RuntimeSettingExtension\nend\n"),
        ),
        (
            "module escape",
            format!(
                "{SOURCE}\nclass ExtendedSettingOwner\n  def self.module_object\n    RuntimeSettingExtension\n  end\nend\n"
            ),
        ),
        (
            "custom extend_object",
            SOURCE.replacen(
                "  @values = 701",
                "  def self.extend_object(owner)\n    super\n  end\n  @values = 701",
                1,
            ),
        ),
        (
            "optional producer ABI",
            SOURCE.replacen(
                "def setup_methods(name, delta)",
                "def setup_methods(name, delta = 0)",
                1,
            ),
        ),
        (
            "producer Method identity",
            SOURCE.replacen(
                "    key = input.to_sym",
                "    bound = method(:setup_methods)\n    key = input.to_sym",
                1,
            ),
        ),
        (
            "dynamic producer Method identity",
            SOURCE.replacen(
                "    key = input.to_sym",
                "    bound = method(input.to_sym)\n    key = input.to_sym",
                1,
            ),
        ),
        (
            "wrong source arity",
            SOURCE.replacen(
                "setup_methods(:from_body, 7)",
                "setup_methods(:from_body)",
                1,
            ),
        ),
        (
            "wrong callback send arity",
            SOURCE.replacen(
                "base.send(:setup_methods, :hook_value, 5)",
                "base.send(:setup_methods, :hook_value)",
                1,
            ),
        ),
        (
            "unresolved template",
            SOURCE.replacen("@values[name] + delta", "@unknown_values[name] + delta", 1),
        ),
    ];
    for (label, source) in cases {
        let (_, typed, errors) =
            app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(typed.runtime_definition_families.is_empty(), "{label}");
        assert!(
            errors.iter().any(|error| error
                .message
                .contains("runtime-defined method not supported")),
            "{label}: {errors:#?}"
        );
    }
}

#[test]
fn declared_untyped_hook_argument_is_not_replaced_by_owner_inference() {
    let (_, typed, errors) = app(SOURCE)
        .write(
            "sig/runtime_setting_extension.rbs",
            "module RuntimeSettingExtension\n  def self.extended: (untyped base) -> nil\nend\n",
        )
        .emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(typed.runtime_definition_families.is_empty());
    assert!(
        errors.iter().any(|error| error
            .message
            .contains("runtime-defined method not supported")),
        "{errors:#?}"
    );
}

#[test]
fn producer_arguments_are_inferred_from_actual_owner_calls() {
    let source = SOURCE
        .replace("  #: (Symbol name, Integer delta) -> Symbol\n", "")
        .replace("  #: (singleton(ExtendedSettingOwner) base) -> nil\n", "");
    assert_original_and_lowered(&source);
}

#[test]
#[ignore = "requires the audited whole-original settings input; diagnostic output never executed"]
fn actual_original_extension_retains_its_owner_and_factory_diagnostic() {
    let input =
        std::env::var("ROUNDHOUSE_ORIGINAL_SETTINGS_APP").expect("audited original input required");
    let mut typed = roundhouse::ingest::ingest_app_for_target(std::path::Path::new(&input), roundhouse::project::BuildTarget::Spinel).unwrap();
    let _diagnostics = roundhouse::session::analyze_and_lower_for(
        &mut typed,
        roundhouse::project::BuildTarget::Spinel,
    );
    let event = typed
        .runtime_extension_events
        .iter()
        .find(|event| event.module.0.as_str() == "SiteSettingExtension")
        .expect("real source extension event");
    assert_eq!(event.owner.0.as_str(), "SiteSetting");
    assert!(
        !typed
            .runtime_definition_families
            .iter()
            .any(|family| family.owner.0.as_str() == "SiteSetting"),
        "revisit this diagnostic experiment when the original factory closes"
    );
    let module = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "SiteSettingExtension")
        .unwrap();
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_SETTINGS_IR") {
        std::fs::write(output, serde_json::to_string_pretty(module).unwrap()).unwrap();
    }
}

#[test]
fn literal_argument_evidence_respects_builtin_reflection_and_overrides() {
    for (label, parent, override_method, expected) in [
        ("builtin", "", "", true),
        (
            "own override",
            "",
            "def self.send(name, value); nil; end",
            false,
        ),
        ("inherited override", " < ReflectiveParent", "", false),
    ] {
        let source = format!(
            "class ReflectiveParent\n def self.send(name, value); nil; end\nend\nclass LiteralArgumentOwner{parent}\n {override_method}\n def self.accept(value); value; end\n def self.exercise; send(:accept, 17); end\nend\n"
        );
        let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let method = typed
            .library_classes
            .iter()
            .find(|class| class.name.0.as_str() == "LiteralArgumentOwner")
            .unwrap()
            .methods
            .iter()
            .find(|method| method.name.as_str() == "accept")
            .unwrap();
        let observed_integer = matches!(&method.signature, Some(roundhouse::ty::Ty::Fn { params, .. }) if params.first().is_some_and(|param| *param.ty == roundhouse::ty::Ty::Int));
        assert_eq!(observed_integer, expected, "{label}: {method:#?}");
    }
}

#[test]
fn actual_memoized_reader_index_writes_type_the_owned_storage() {
    assert_original_and_lowered(&with_reader_storage(SOURCE));
}

fn with_reader_storage(source: &str) -> String {
    let source = source.replace("  #: (Symbol name, Integer delta) -> Symbol\n", "").replace("  def setup_methods(name, delta)", "  def themeable\n    @themeable ||= {}\n  end\n  def setting(name_arg, enabled)\n    name = name_arg.to_sym\n    themeable[name] = enabled ? true : false\n  end\n  def setup_methods(name, delta)");
    let source = source.replace("    declaring = self", "    setting(name, delta > 0)\n    declaring = self").replace("      @values[name] + delta", "      raise \"lost reader storage\" unless themeable[name]\n      @values[name] + delta");
    let source = source.replace(
        "    ChildExtendedSettingOwner.seed",
        "    ChildExtendedSettingOwner.setting(key, true)\n    ChildExtendedSettingOwner.seed",
    );
    source
}

#[test]
fn unknown_and_other_receiver_reader_writes_do_not_close_owner_storage() {
    let source = with_reader_storage(SOURCE);
    let cases = [
        (
            "unknown value writer",
            source.replace("enabled ? true : false", "unknown_value_producer"),
        ),
        (
            "other receiver",
            format!(
                "{}\nclass OtherFlagOwner\n def self.themeable; {{}}; end\nend\n",
                source.replace(
                    "themeable[name] = enabled ? true : false",
                    "OtherFlagOwner.themeable[name] = enabled ? true : false"
                )
            ),
        ),
        (
            "non-memoized reader",
            source.replace("@themeable ||= {}", "{}"),
        ),
    ];
    for (label, source) in cases {
        let (_, typed, errors) =
            app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(typed.runtime_definition_families.is_empty(), "{label}");
        assert!(
            errors.iter().any(|error| error
                .message
                .contains("runtime-defined method not supported")),
            "{label}: {errors:#?}"
        );
    }
}


fn with_per_site_reader_storage(source: &str) -> String {
    with_reader_storage(source).replace(
        "    @themeable ||= {}",
        "    @themeable ||= {}\n    @themeable[site_key] ||= {}",
    ).replace("  def themeable", "  def select_site(site)\n    @site_reads = 0\n    @site = site\n  end\n  def site_reads\n    @site_reads\n  end\n  def site_key\n    @site_reads ||= 0\n    @site_reads += 1\n    @site || 'initial'\n  end\n  def themeable")
    .replace("    ChildExtendedSettingOwner.setting(key, true)",
        "    select_site('second')\n    setting(key, false)\n    raise 'index repeated on write' unless site_reads == 1\n    raise 'second site value frozen' unless themeable[key] == false\n    raise 'index repeated on read' unless site_reads == 2\n    select_site('initial')\n    raise 'original site storage lost' unless themeable[key]\n    raise 'index repeated on cached read' unless site_reads == 1\n    ChildExtendedSettingOwner.setting(key, true)")
}

#[test]
fn per_site_memoized_reader_index_writes_keep_nested_storage_types() {
    assert_original_and_lowered(&with_per_site_reader_storage(SOURCE));
}

#[test]
fn per_site_reader_keeps_unknown_and_nonmemoized_storage_debt() {
    let source = with_per_site_reader_storage(SOURCE);
    for source in [
        source.replace("@site || 'initial'", "unknown_site_key"),
        source.replace("enabled ? true : false", "unknown_value_producer"),
        source.replace("@themeable[site_key] ||= {}", "@themeable[site_key].dup"),
        source.replace("@themeable[site_key] ||= {}", "@other[site_key] ||= {}"),
    ] {
        let (_, typed, errors) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(typed.runtime_definition_families.is_empty(), "unproved nested storage admitted");
        assert!(errors.iter().any(|error| error.message.contains("runtime-defined method not supported")), "{errors:#?}");
    }
}

//! Plugin::Instance.parse_from_source builds via implicit Class#new.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"class SourcePluginFactory
  attr_reader :path
  def self.parse(path)
    new(path)
  end
  def initialize(path = nil)
    @path = path
  end
  def self.exercise
    instance = parse("source path")
    raise "factory argument lost" unless instance.path == "source path"
    raise "optional nil erased" unless new.path.nil?
    puts "source implicit constructor PASS"
  end
end
"#;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/source_plugin_factory.rb", source)
}
#[test]
fn actual_factory_arguments_reach_the_real_initializer_without_annotations() {
    use roundhouse::ty::Ty;
    for source in [
        SOURCE.to_string(),
        SOURCE.replace("    new(path)", "    self.new(path)"),
    ] {
        let (emitted, typed, errors) =
            app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(errors.is_empty(), "{errors:#?}");
        let class = typed
            .library_classes
            .iter()
            .find(|c| c.name.0.as_str() == "SourcePluginFactory")
            .unwrap();
        let initializer = class
            .methods
            .iter()
            .find(|m| m.name.as_str() == "initialize")
            .unwrap();
        assert!(
            matches!(&initializer.body.ty, Some(Ty::Union { variants }) if variants.contains(&Ty::Str) && variants.contains(&Ty::Nil)),
            "{initializer:#?}"
        );
        let factory = class
            .methods
            .iter()
            .find(|m| m.name.as_str() == "parse")
            .unwrap();
        assert!(
            matches!(&factory.signature, Some(Ty::Fn { ret, .. }) if **ret == Ty::SelfInstance),
            "{factory:#?}"
        );
        fn closed(expr: &roundhouse::expr::Expr) {
            assert!(
                expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
                "{expr:#?}"
            );
            expr.node.for_each_child(&mut closed);
        }
        for method in &class.methods {
            closed(&method.body);
        }
        let original = emit_and_run::ruby()
            .args(["-e", &format!("{source}\nSourcePluginFactory.exercise")])
            .output()
            .unwrap();
        let lowered = emit_and_run::ruby()
            .args([
                "-e",
                "require_relative 'app/models'; SourcePluginFactory.exercise",
            ])
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(
            original.status.success(),
            "{}",
            String::from_utf8_lossy(&original.stderr)
        );
        assert!(
            lowered.status.success(),
            "{}",
            String::from_utf8_lossy(&lowered.stderr)
        );
        assert_eq!(lowered.stdout, original.stdout);
    }
}
#[test]
fn custom_constructors_and_unproved_descendant_initializers_supply_no_builtin_site() {
    use roundhouse::ty::Ty;
    for (label, extra, parent, header, call) in [
        (
            "own new",
            "def self.new(value = nil); :other_result; end",
            "",
            "",
            "",
        ),
        (
            "global Class new override",
            "",
            "",
            "class Class\n def new(value = nil); :other_result; end\nend\n",
            "",
        ),
        (
            "inherited new",
            "",
            " < ConstructorParent",
            "class ConstructorParent\n def self.new(value = nil); :other_result; end\nend\n",
            "",
        ),
        (
            "unknown descendant initialization",
            "",
            "",
            "",
            "class ConstructorChild < SourcePluginFactory\n def initialize(path); @path = 71; end\nend\n",
        ),
    ] {
        let source = format!(
            "{header}class SourcePluginFactory{parent}\n {extra}\n def self.parse(path)\n new(path)\n end\n def initialize(path = nil)\n @path = path\n end\n def self.exercise\n parse(\"observed source\")\n end\nend\n{call}"
        );
        let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let method = typed
            .library_classes
            .iter()
            .find(|c| c.name.0.as_str() == "SourcePluginFactory")
            .unwrap()
            .methods
            .iter()
            .find(|m| m.name.as_str() == "initialize")
            .unwrap();
        assert!(
            !matches!(&method.body.ty, Some(Ty::Str))
                && !matches!(&method.body.ty, Some(Ty::Union { variants }) if variants.contains(&Ty::Str)),
            "{label}: {method:#?}"
        );
    }
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn original_implicit_factory_argument_and_nil_semantics_run_natively() {
    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("probe.rb"),
        "require_relative 'app/models'; SourcePluginFactory.exercise\n",
    )
    .unwrap();
    let compiled =
        std::process::Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
            .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
            .current_dir(&*emitted)
            .output()
            .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(emitted.join("probe"))
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(native.stdout, b"source implicit constructor PASS\n");
}

#[test]
#[ignore = "requires audited original settings input; diagnostic output never executed"]
fn actual_plugin_factory_closes_path_and_metadata_but_not_enabled_setting_configuration() {
    use roundhouse::ty::Ty;
    let input =
        std::env::var("ROUNDHOUSE_ORIGINAL_SETTINGS_APP").expect("audited original input required");
    let mut app = roundhouse::ingest::ingest_app(std::path::Path::new(&input)).unwrap();
    let _diagnostics = roundhouse::session::analyze_and_lower_for(
        &mut app,
        roundhouse::project::BuildTarget::Spinel,
    );
    let class = app
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "Plugin::Instance")
        .unwrap();
    let path = class
        .methods
        .iter()
        .find(|m| m.name.as_str() == "path")
        .unwrap();
    assert!(
        matches!(&path.signature, Some(Ty::Fn { ret, .. }) if !ret.mentions_unknown() && matches!(&**ret, Ty::Union { variants } if variants.contains(&Ty::Str) && variants.contains(&Ty::Nil))),
        "{path:#?}"
    );
    let metadata = class
        .methods
        .iter()
        .find(|m| m.name.as_str() == "metadata")
        .unwrap();
    assert!(
        matches!(&metadata.signature, Some(Ty::Fn { ret, .. }) if !ret.mentions_unknown() && matches!(&**ret, Ty::Union { variants } if variants.contains(&Ty::Nil) && variants.iter().any(|ty| matches!(ty, Ty::Class { id, .. } if id.0.as_str() == "Plugin::Metadata")))),
        "{metadata:#?}"
    );
    let enabled = class
        .methods
        .iter()
        .find(|m| m.name.as_str() == "enabled_site_setting")
        .unwrap();
    assert!(
        matches!(&enabled.signature, Some(Ty::Fn { ret, .. }) if ret.mentions_unknown()),
        "missing external configuration producer must stay open: {enabled:#?}"
    );
    assert!(
        !app.runtime_definition_families
            .iter()
            .any(|family| family.owner.0.as_str() == "SiteSetting")
    );
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_PLUGIN_IR") {
        std::fs::write(output, serde_json::to_string_pretty(class).unwrap()).unwrap();
    }
}

#[test]
fn an_explicit_gradual_initializer_parameter_is_not_replaced_by_factory_evidence() {
    let source = SOURCE.replace(
        "  def initialize(path = nil)",
        "  #: (?untyped path) -> void\n  def initialize(path = nil)",
    );
    let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(
        typed
            .rbs_signatures
            .get(&roundhouse::ClassId(roundhouse::Symbol::from(
                "SourcePluginFactory"
            )))
            .is_some_and(|methods| methods.contains_key(&roundhouse::Symbol::from("initialize"))),
        "the optional source declaration must actually be parsed"
    );
    let method = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "SourcePluginFactory")
        .unwrap()
        .methods
        .iter()
        .find(|m| m.name.as_str() == "initialize")
        .unwrap();
    assert!(
        method
            .body
            .ty
            .as_ref()
            .is_none_or(roundhouse::ty::Ty::mentions_unknown),
        "{method:#?} declarations={:#?}",
        typed.rbs_signatures
    );
}

#[test]
fn an_unknown_passed_factory_argument_does_not_become_the_nil_default() {
    let source = SOURCE.replace("parse(\"source path\")", "parse(unknown_source_path)");
    let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    let method = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "SourcePluginFactory")
        .unwrap()
        .methods
        .iter()
        .find(|m| m.name.as_str() == "initialize")
        .unwrap();
    assert!(
        method
            .body
            .ty
            .as_ref()
            .is_none_or(roundhouse::ty::Ty::mentions_unknown),
        "{method:#?}"
    );
}

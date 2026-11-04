//! Reduced owning shape from original GlobalSetting.load_defaults: real
//! computed class-ivar addresses, lazy provider reads and a missing sentinel.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
const SOURCE: &str = r#"class CachedDefinitionOwner
  #: (Hash[Symbol, Integer | bool | String | nil] values) -> Integer
  def self.seed(values)
    @values = values
    @reads = 0
  end
  #: () -> Integer
  def self.reads
    @reads
  end
  #: (Symbol key) -> Symbol
  def self.install(key)
    instance_variable_set("@#{key}_cache", nil)
    define_singleton_method(key) do
      val = instance_variable_get("@#{key}_cache")
      if val.nil?
        @reads = @reads + 1
        val = @values[key]
        val = :missing if val.nil?
        instance_variable_set("@#{key}_cache", val)
      end
      val == :missing ? nil : val
    end
  end
  #: (String input) -> nil
  def self.exercise(input)
    key = input.to_sym
    seed({key => false})
    install(key)
    raise "cached false" unless public_send(key) == false && reads == 1
    raise "false treated as missing" unless public_send(key) == false && reads == 1
    ChildCachedDefinitionOwner.seed({key => 29})
    raise "inherited cache instead of receiver cache" unless ChildCachedDefinitionOwner.public_send(key) == 29
    raise "child read count" unless ChildCachedDefinitionOwner.reads == 1
    seed({key => nil})
    install(key)
    raise "missing sentinel escaped" unless public_send(key).nil? && reads == 1
    raise "missing read repeated" unless public_send(key).nil? && reads == 1
    raise "child cache invalidated" unless ChildCachedDefinitionOwner.public_send(key) == 29
    puts "computed cache PASS"
  end
end
class ChildCachedDefinitionOwner < CachedDefinitionOwner
end
"#;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/cached_definition_owner.rb", SOURCE)
}

#[test]
fn computed_cache_matches_original_and_lowered() {
    let (emitted, app, errors) = app().emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    assert_eq!(app.runtime_class_storage_patterns.len(), 1);
    assert_eq!(app.runtime_class_storage_patterns[0].prefix, "@");
    assert_eq!(app.runtime_class_storage_patterns[0].suffix, "_cache");
    assert!(
        !app.runtime_class_storage_patterns[0]
            .value
            .mentions_unknown()
    );
    assert_eq!(app.runtime_definition_families.len(), 1);
    let original = emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!(
            "{SOURCE}\nCachedDefinitionOwner.exercise('cache_from_runtime')"
        ))
        .output()
        .unwrap();
    let lowered = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e", "require_relative 'app/models/cached_definition_owner'; require_relative 'app/models/child_cached_definition_owner'; CachedDefinitionOwner.exercise('cache_from_runtime')"])
        .current_dir(&*emitted).output().unwrap();
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
    assert_eq!(original.stdout, lowered.stdout);
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn computed_cache_runs_natively() {
    let (emitted, errors) = app().emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(emitted.join("cache.rb"), "require_relative 'app/models/cached_definition_owner'; require_relative 'app/models/child_cached_definition_owner'; CachedDefinitionOwner.exercise(ARGV.fetch(0))\n").unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let native = std::process::Command::new(compiler)
        .args(["--jobs=4", "--rbs", ".", "cache.rb", "-o", "cache"])
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    let result = std::process::Command::new(emitted.join("cache"))
        .arg("cache_from_runtime")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        result.status.success(),
        "{}",
        String::from_utf8_lossy(&result.stderr)
    );
    assert_eq!(result.stdout, b"computed cache PASS\n");
}

#[test]
fn every_cached_template_and_runtime_body_is_closed() {
    let (_, typed, errors) = app().emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    assert_closed_templates(&typed);
}

fn assert_closed_templates(typed: &roundhouse::App) {
    fn check(expr: &roundhouse::expr::Expr) {
        assert!(
            expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
            "{expr:#?}"
        );
        expr.node.for_each_child(&mut check);
    }
    fn templates(expr: &roundhouse::expr::Expr) {
        if let roundhouse::expr::ExprNode::Send {
            recv: Some(recv),
            method,
            args,
            ..
        } = &*expr.node
            && method.as_str() == "install"
            && matches!(&*recv.node, roundhouse::expr::ExprNode::Const { path } if path.first().is_some_and(|name| name.as_str().starts_with("RoundhouseRuntimeFamily")))
        {
            check(&args[2]);
        }
        expr.node.for_each_child(&mut templates);
    }
    for class in &typed.library_classes {
        for method in &class.methods {
            if class.name.0.as_str().starts_with("RoundhouseRuntimeFamily") {
                check(&method.body);
            }
            templates(&method.body);
        }
    }
}

#[test]
fn unknown_or_incompatible_cache_writers_keep_original_refusal() {
    for (label, source) in [
        ("unknown address", SOURCE.replace("def self.reads", "def self.unbounded(address, value)\n    instance_variable_set(address, value)\n  end\n  def self.reads")),
        ("two namespaces", SOURCE.replace("instance_variable_set(\"@#{key}_cache\", nil)", "instance_variable_set(\"@#{key}_other\", 17)\n    instance_variable_set(\"@#{key}_cache\", nil)")),
        ("incompatible child writer", SOURCE.replace("class ChildCachedDefinitionOwner < CachedDefinitionOwner\nend", "class ChildCachedDefinitionOwner < CachedDefinitionOwner\n  #: (Symbol key) -> Array[Integer]\n  def self.corrupt(key)\n    instance_variable_set(\"@#{key}_cache\", [1])\n  end\nend")),
    ] {
        let (_, typed, _) = emit_and_run::empty_app().write("config/routes.rb", "Rails.application.routes.draw do\nend\n").write("lib/cached_definition_owner.rb", &source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(typed.runtime_definition_families.is_empty(), "{label}");
    }
}

#[test]
#[ignore = "requires an audited original GlobalSetting projection via ROUNDHOUSE_ORIGINAL_GLOBAL_SETTING_APP"]
fn original_factory_templates_have_closed_types() {
    let input = std::env::var("ROUNDHOUSE_ORIGINAL_GLOBAL_SETTING_APP")
        .expect("audited original input required");
    let mut typed = roundhouse::ingest::ingest_app(std::path::Path::new(&input)).unwrap();
    let _ = roundhouse::session::analyze_and_lower_for(
        &mut typed,
        roundhouse::project::BuildTarget::Spinel,
    );
    assert_eq!(typed.runtime_definition_families.len(), 1);
    let family = &typed.runtime_definition_families[0];
    assert_eq!(family.owner.0.as_str(), "GlobalSetting");
    assert_eq!(
        family.original_installs.len(),
        3,
        "original register/load_defaults/add_default events"
    );
    assert_closed_templates(&typed);
    let owner = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "GlobalSetting")
        .unwrap();
    for name in ["register", "add_default", "load_defaults", "configure!"] {
        let method = owner
            .methods
            .iter()
            .find(|method| method.name.as_str() == name)
            .unwrap();
        let Some(roundhouse::ty::Ty::Fn { ret, .. }) = &method.signature else {
            panic!("{method:#?}");
        };
        assert!(
            !ret.mentions_unknown(),
            "actual original public {name} ABI remained untyped: {ret:?}"
        );
    }
}

#[test]
fn unsupported_event_reports_callable_obligations_without_losing_refusal() {
    let source = SOURCE.replace(
        "define_singleton_method(key) do",
        "define_singleton_method(key) do |scoped_to = nil|",
    );
    let (_, errors) = emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/cached_definition_owner.rb", &source)
        .emit(roundhouse::project::BuildTarget::Spinel);
    assert!(
        errors.iter().any(
            |error| error.contains("runtime-defined method not supported")
                && error.contains("argument/optional-argument callable ABI remains unproved")
        ),
        "{errors:#?}"
    );
}

#[test]
fn inferred_factory_return_is_refreshed_after_event_lowering() {
    let source = SOURCE.replace(
        "  #: (Symbol key) -> Symbol\n  def self.install",
        "  def self.install",
    );
    let (_, typed, errors) = emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/cached_definition_owner.rb", &source)
        .emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let method = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "CachedDefinitionOwner")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "install")
        .unwrap();
    let Some(roundhouse::ty::Ty::Fn { ret, .. }) = &method.signature else {
        panic!("{method:#?}");
    };
    assert_eq!(
        **ret,
        roundhouse::ty::Ty::Sym,
        "inferred pre-lowering untyped return must not become authoritative"
    );
    assert!(!typed.inferred_method_signatures.is_empty());
    let encoded = serde_json::to_string(&typed.inferred_method_signatures).unwrap();
    let decoded: Vec<roundhouse::app::InferredMethodSignature> =
        serde_json::from_str(&encoded).unwrap();
    assert_eq!(decoded, typed.inferred_method_signatures);
}

#[test]
fn explicit_gradual_factory_contract_remains_authoritative() {
    let source = SOURCE.replace("#: (Symbol key) -> Symbol", "#: (Symbol key) -> untyped");
    let (_, typed, errors) = emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/cached_definition_owner.rb", &source)
        .emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let method = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "CachedDefinitionOwner")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "install")
        .unwrap();
    let Some(roundhouse::ty::Ty::Fn { ret, .. }) = &method.signature else {
        panic!("{method:#?}");
    };
    assert_eq!(
        **ret,
        roundhouse::ty::Ty::Untyped,
        "do not replace a source-declared gradual contract"
    );
}

//! Reduced from Plugin::Instance.find_all's [].tap / nested each / << producer.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"class PluginDescriptor
  def enabled?
    true
  end
  def name
    "fixture"
  end
end
class PluginScan
  def self.parse_from_source(path)
    PluginDescriptor.new
  end
  def self.find_all(parent_path)
    [].tap do |plugins|
      ["first", "second"].each do |path|
        plugins << parse_from_source(path)
      end
    end
  end
  def self.exercise
    plugins = find_all("unused fixture path")
    raise "array size" unless plugins.length == 2
    raise "plugin class" unless plugins.all? { |plugin| plugin.enabled? }
    puts "source plugin accumulator PASS"
  end
end
class PluginTableSource
  def initialize
    @plugins_by_name = 41
  end
  def instance_marker
    @plugins_by_name
  end
  def self.populate
    @plugins_by_name = {}
    PluginScan.find_all("fixture").each do |plugin|
      @plugins_by_name[plugin.name] = plugin
    end
    nil
  end
  def self.plugins_by_name
    @plugins_by_name ||= {}
  end
  def self.exercise
    raise "instance/class storage mixed" unless new.instance_marker == 41
    raise "early registry" unless plugins_by_name.empty?
    populate
    plugin = plugins_by_name["fixture"]
    raise "registry class/value" unless plugin.enabled?
    missing = plugins_by_name["missing"]
    begin
      missing.enabled?
      raise "missing plugin predicate was called on nil"
    rescue NoMethodError
      nil
    end
    puts "source plugin registry PASS"
  end
end
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/plugin_scan.rb", source)
}

#[test]
fn original_plugin_accumulator_has_closed_element_type() {
    let (_, typed, errors) = app(SOURCE).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let method = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "PluginScan")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "find_all")
        .unwrap();
    let Some(roundhouse::ty::Ty::Fn { ret, .. }) = &method.signature else {
        panic!("{method:#?}")
    };
    assert!(
        matches!(&**ret, roundhouse::ty::Ty::Array { elem } if matches!(&**elem, roundhouse::ty::Ty::Class { id, .. } if id.0.as_str() == "PluginDescriptor")),
        "{ret:#?}"
    );
    fn closed(expr: &roundhouse::expr::Expr) {
        assert!(
            expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
            "{expr:#?}"
        );
        expr.node.for_each_child(&mut closed);
    }
    for method in typed
        .library_classes
        .iter()
        .filter(|class| matches!(class.name.0.as_str(), "PluginScan" | "PluginTableSource"))
        .flat_map(|class| &class.methods)
    {
        closed(&method.body);
    }
    let original = emit_and_run::ruby()
        .args([
            "-e",
            &format!("{SOURCE}\nPluginScan.exercise; PluginTableSource.exercise"),
        ])
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let lowered = emit_and_run::ruby()
        .args([
            "-e",
            "require_relative 'app/models'; PluginScan.exercise; PluginTableSource.exercise",
        ])
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
fn source_plugin_accumulator_runs_natively() {
    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("scan.rb"),
        "require_relative 'app/models'; PluginScan.exercise; PluginTableSource.exercise\n",
    )
    .unwrap();
    let compiled =
        std::process::Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
            .args(["--jobs=4", "--rbs", ".", "scan.rb", "-o", "scan"])
            .current_dir(&*emitted)
            .output()
            .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(emitted.join("scan"))
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(
        native.stdout,
        b"source plugin accumulator PASS\nsource plugin registry PASS\n"
    );
}

#[test]
fn uncertain_aliases_unknown_writes_and_discarded_block_values_stay_open() {
    let original = "plugins << parse_from_source(path)";
    let cases = [
        (
            "discarded result",
            SOURCE.replace(original, "parse_from_source(path)"),
        ),
        (
            "unknown writer",
            SOURCE.replace(original, "plugins << unknown_plugin"),
        ),
        (
            "rebound parameter",
            SOURCE.replace(original, "plugins = []; plugins << parse_from_source(path)"),
        ),
        (
            "escaped parameter",
            SOURCE.replace(
                original,
                "hand_to_unknown(plugins); plugins << parse_from_source(path)",
            ),
        ),
        (
            "shadowed parameter",
            SOURCE.replace("do |path|", "do |plugins|"),
        ),
        (
            "core tap override",
            format!("class Object\n def tap; yield 17; self; end\nend\n{SOURCE}"),
        ),
        (
            "included tap override",
            format!(
                "module TapOverride\n def tap; yield 17; self; end\nend\nclass Array\n include TapOverride\nend\n{SOURCE}"
            ),
        ),
        (
            "escaping tap break",
            SOURCE.replace(
                "      [\"first\", \"second\"].each",
                "      break 17\n      [\"first\", \"second\"].each",
            ),
        ),
    ];
    for (label, source) in cases {
        let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let method = typed
            .library_classes
            .iter()
            .find(|class| class.name.0.as_str() == "PluginScan")
            .unwrap()
            .methods
            .iter()
            .find(|method| method.name.as_str() == "find_all")
            .unwrap();
        assert!(
            !matches!(&method.signature, Some(roundhouse::ty::Ty::Fn { ret, .. }) if matches!(&**ret, roundhouse::ty::Ty::Array { elem } if !elem.mentions_unknown())),
            "{label}: {method:#?}"
        );
    }
}

#[test]
fn original_singleton_registry_does_not_keep_stale_empty_seed_types() {
    let (_, typed, errors) = app(SOURCE).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let method = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "PluginTableSource")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "plugins_by_name")
        .unwrap();
    assert!(
        matches!(&method.signature, Some(roundhouse::ty::Ty::Fn { ret, .. }) if matches!(&**ret, roundhouse::ty::Ty::Hash { key, value } if **key == roundhouse::ty::Ty::Str && matches!(&**value, roundhouse::ty::Ty::Class { id, .. } if id.0.as_str() == "PluginDescriptor"))),
        "{method:#?}"
    );
}

#[test]
fn uncertain_singleton_writers_remain_type_debt() {
    use roundhouse::ty::Ty;
    for (label, extra) in [
        (
            "unknown value",
            "@plugins_by_name[\"other\"] = unknown_plugin",
        ),
        (
            "unproved mutator",
            "@plugins_by_name.store(\"other\", unknown_plugin)",
        ),
        ("truthy non-Hash write", "@plugins_by_name = true"),
        (
            "unknown aliased writer",
            r#"alias_table = @plugins_by_name; alias_table["other"] = unknown_plugin"#,
        ),
        ("escaped table", "unknown_consumer(@plugins_by_name)"),
        ("returned table alias", "@plugins_by_name"),
        (
            "dynamic reflective write",
            "instance_variable_set(unknown_field_name, unknown_plugin)",
        ),
        (
            "reflective setter dispatch",
            "send(:instance_variable_set, :@plugins_by_name, unknown_plugin)",
        ),
    ] {
        let source = SOURCE.replace(
            "  def self.populate",
            &format!("  def self.other_writer\n    {extra}\n  end\n  def self.populate"),
        );
        let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let method = typed
            .library_classes
            .iter()
            .find(|class| class.name.0.as_str() == "PluginTableSource")
            .unwrap()
            .methods
            .iter()
            .find(|method| method.name.as_str() == "plugins_by_name")
            .unwrap();
        assert!(
            method
                .signature
                .as_ref()
                .is_none_or(|signature| match signature {
                    Ty::Fn { ret, .. } => ret.mentions_unknown(),
                    _ => true,
                }),
            "{label}: {method:#?}"
        );
    }
}

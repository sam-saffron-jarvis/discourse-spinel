//! Source String iterator contract reduced from Plugin::Metadata.parse.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r##"class SourceLineMetadata
  def initialize
    @count = 0
  end
  def self.parse(text)
    metadata = new
    text.each_line { |line| break unless metadata.parse_line(line) }
    metadata
  end
  def parse_line(line)
    line = line.strip
    return false unless line[0] == "#"
    @count += 1
    true
  end
  def count
    @count
  end
  def self.receiver_result
    "#one\n#two\n".each_line { |line| line.strip }
  end
  def self.break_result
    "#one\nstop\n#unseen\n".each_line { |line| break :stopped if line == "stop\n" }
  end
  def self.exercise
    parsed = parse("#one\n#two\nstop\n#unseen\n")
    raise "source line count/order" unless parsed.count == 2
    raise "iterator receiver result" unless receiver_result == "#one\n#two\n"
    raise "escaping break result" unless break_result == :stopped
    puts "source metadata line producer PASS"
  end
end
"##;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/source_line_metadata.rb", source)
}

#[test]
fn actual_line_yields_close_the_source_parser_without_a_parameter_annotation() {
    let (emitted, typed, errors) =
        app(SOURCE).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let class = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "SourceLineMetadata")
        .unwrap();
    if let Ok(output) = std::env::var("ROUNDHOUSE_REDUCED_METADATA_IR") {
        std::fs::write(output, serde_json::to_string_pretty(class).unwrap()).unwrap();
    }
    let method = class
        .methods
        .iter()
        .find(|m| m.name.as_str() == "parse_line")
        .unwrap();
    assert!(
        matches!(&method.signature, Some(roundhouse::ty::Ty::Fn { params, .. }) if *params[0].ty == roundhouse::ty::Ty::Str),
        "{method:#?}"
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
        .args(["-e", &format!("{SOURCE}\nSourceLineMetadata.exercise")])
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let lowered = emit_and_run::ruby()
        .args([
            "-e",
            "require_relative 'app/models'; SourceLineMetadata.exercise",
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
fn source_metadata_line_iteration_runs_natively() {
    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("probe.rb"),
        "require_relative 'app/models'; SourceLineMetadata.exercise\n",
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
    assert_eq!(native.stdout, b"source metadata line producer PASS\n");
}

#[test]
fn unknown_blockless_and_overridden_iterators_do_not_borrow_the_core_contract() {
    use roundhouse::expr::ExprNode;
    use roundhouse::ty::Ty;
    for (label, prefix, receiver, tail) in [
        ("blockless", "", "\"one\"", ".each_line"),
        (
            "unknown receiver",
            "",
            "unknown_source",
            ".each_line { |line| line }",
        ),
        (
            "direct override",
            "class String\n def each_line; yield 17; :custom; end\nend\n",
            "\"one\"",
            ".each_line { |line| line }",
        ),
        (
            "included override",
            "module LineOverride\n def each_line; yield 17; :custom; end\nend\nclass String\n include LineOverride\nend\n",
            "\"one\"",
            ".each_line { |line| line }",
        ),
        (
            "unknown break",
            "",
            "\"one\"",
            ".each_line { |line| break unknown_result }",
        ),
    ] {
        let source = format!(
            "{prefix}class LineContractProbe\n def self.probe\n {receiver}{tail}\n end\nend\n"
        );
        let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let method = typed
            .library_classes
            .iter()
            .find(|c| c.name.0.as_str() == "LineContractProbe")
            .unwrap()
            .methods
            .iter()
            .find(|m| m.name.as_str() == "probe")
            .unwrap();
        if label.contains("override") {
            fn check(expr: &roundhouse::expr::Expr) {
                if matches!(&*expr.node, ExprNode::Var { name, .. } if name.as_str() == "line") {
                    assert_ne!(expr.ty, Some(Ty::Str), "{expr:#?}");
                }
                expr.node.for_each_child(&mut check);
            }
            check(&method.body);
        } else {
            assert!(
                method.body.ty.as_ref().is_none_or(Ty::mentions_unknown),
                "{label}: {method:#?}"
            );
        }
    }
}

#[test]
fn nested_iterator_and_loop_breaks_do_not_change_the_outer_receiver_result() {
    use roundhouse::ty::Ty;
    let source = r#"class LineContractProbe
  def self.probe
    "one\ntwo\n".each_line do |line|
      [1].each { break :inner }
      while true
        break :loop
      end
      line.strip
    end
  end
end
"#;
    let (_, typed, errors) = app(source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let method = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "LineContractProbe")
        .unwrap()
        .methods
        .iter()
        .find(|m| m.name.as_str() == "probe")
        .unwrap();
    assert_eq!(method.body.ty, Some(Ty::Str), "{method:#?}");
}

#[test]
#[ignore = "requires audited whole-original settings input; diagnostic output never executed"]
fn actual_original_metadata_keeps_its_real_line_producer_and_unknown_configuration() {
    use roundhouse::ty::Ty;
    let input =
        std::env::var("ROUNDHOUSE_ORIGINAL_SETTINGS_APP").expect("audited original input required");
    let mut app = roundhouse::ingest::ingest_app(std::path::Path::new(&input)).unwrap();
    let _diagnostics = roundhouse::session::analyze_and_lower_for(
        &mut app,
        roundhouse::project::BuildTarget::Spinel,
    );
    let metadata = app
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "Plugin::Metadata")
        .expect("whole original Metadata");
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_METADATA_IR") {
        std::fs::write(output, serde_json::to_string_pretty(metadata).unwrap()).unwrap();
    }
    let parse_line = metadata
        .methods
        .iter()
        .find(|m| m.name.as_str() == "parse_line")
        .unwrap();
    assert!(
        matches!(&parse_line.signature, Some(Ty::Fn { params, .. }) if *params[0].ty == Ty::Str),
        "{parse_line:#?}"
    );
    let name = metadata
        .methods
        .iter()
        .find(|m| m.name.as_str() == "name")
        .expect("original finite FIELDS accessor");
    assert!(
        matches!(&name.signature, Some(Ty::Fn { ret, .. }) if !ret.mentions_unknown() && matches!(&**ret, Ty::Union { variants } if variants.contains(&Ty::Str) && variants.contains(&Ty::Nil))),
        "actual computed writer must retain its source String argument and nil state: {name:#?}"
    );
    fn closed_metadata(expr: &roundhouse::expr::Expr) {
        assert!(
            expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
            "{expr:#?}"
        );
        expr.node.for_each_child(&mut closed_metadata);
    }
    for method in &metadata.methods {
        closed_metadata(&method.body);
    }
    assert!(
        !app.runtime_definition_families
            .iter()
            .any(|f| f.owner.0.as_str() == "SiteSetting"),
        "the original getter is still unsupported"
    );
    if let Ok(output) = std::env::var("ROUNDHOUSE_ORIGINAL_METADATA_IR") {
        std::fs::write(output, serde_json::to_string_pretty(metadata).unwrap()).unwrap();
    }
}

#[test]
fn source_declared_gradual_line_parameter_remains_authoritative() {
    let source = SOURCE.replace(
        "  def parse_line(line)",
        "  #: (untyped line) -> bool\n  def parse_line(line)",
    );
    let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    let method = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "SourceLineMetadata")
        .unwrap()
        .methods
        .iter()
        .find(|m| m.name.as_str() == "parse_line")
        .unwrap();
    assert!(
        matches!(&method.signature, Some(roundhouse::ty::Ty::Fn { params, .. }) if *params[0].ty == roundhouse::ty::Ty::Untyped),
        "{method:#?}"
    );
}

#[test]
fn rebound_self_does_not_attribute_a_late_bound_instance_to_the_lexical_class() {
    let source = r#"class OtherLineOrigin
  def accept(value)
    value
  end
end
class LexicalLineOrigin
  def accept(value)
    value
  end
  def self.rebound
    OtherLineOrigin.class_exec do
      item = new
      item.accept("only the rebound object")
    end
  end
end
"#;
    let (_, typed, _) = app(source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    let method = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "LexicalLineOrigin")
        .unwrap()
        .methods
        .iter()
        .find(|m| m.name.as_str() == "accept")
        .unwrap();
    assert!(
        method.signature.as_ref().is_none_or(|signature| matches!(signature, roundhouse::ty::Ty::Fn { params, .. } if params[0].ty.mentions_unknown()))
            && method.body.ty.as_ref().is_none_or(roundhouse::ty::Ty::mentions_unknown),
        "{method:#?}"
    );
}

//! Real computed public_send writer shape from Plugin::Metadata.parse_line.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
const SOURCE: &str = r##"class SourceComputedMetadata
  FIELDS = %i[name number]
  attr_accessor(*FIELDS)
  attr_reader :log
  def initialize
    @log = ""
  end
  def name=(value)
    @log << "name;"
    @name = value
  end
  def number=(value)
    @log << "number;"
    @number = Integer(value)
  rescue StandardError
    @number = nil
  end
  def self.parse(text)
    metadata = new
    text.each_line { |line| break unless metadata.parse_line(line) }
    metadata
  end
  def parse_line(line)
    line = line.strip
    return false unless line[0] == "#"
    attribute, *value = line[1..-1].split(":")
    attribute = attribute.strip.to_sym
    if FIELDS.include?(attribute)
      public_send("#{attribute}=", value.join(":").strip)
    end
    true
  end
  def self.exercise
    metadata = parse("#name: fixture value\n#number: 41\n#unknown: ignored\nstop\n#name: unseen\n")
    raise "source metadata value" unless metadata.name == "fixture value"
    raise "source writer conversion" unless metadata.number == 41
    raise "source writer order/count" unless metadata.log == "name;number;"
    puts "source computed metadata writer PASS"
  end
end
"##;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/source_computed_metadata.rb", source)
}
#[test]
fn actual_computed_argument_types_close_known_writer_storage_without_rewriting_dispatch() {
    use roundhouse::expr::ExprNode;
    use roundhouse::ty::Ty;
    let (emitted, typed, errors) =
        app(SOURCE).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let class = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "SourceComputedMetadata")
        .unwrap();
    let name = class
        .methods
        .iter()
        .find(|m| m.name.as_str() == "name")
        .unwrap();
    assert!(
        matches!(&name.signature, Some(Ty::Fn { ret, .. }) if matches!(&**ret, Ty::Union { variants } if variants.contains(&Ty::Str) && variants.contains(&Ty::Nil)) && !ret.mentions_unknown()),
        "{name:#?}"
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
    let mut reflections = 0;
    fn visit(expr: &roundhouse::expr::Expr, count: &mut usize) {
        if matches!(&*expr.node, ExprNode::Send { method, args, .. } if method.as_str() == "public_send" && matches!(&*args[0].node, ExprNode::StringInterp { .. }))
        {
            *count += 1;
        }
        expr.node.for_each_child(&mut |child| visit(child, count));
    }
    for method in &class.methods {
        visit(&method.body, &mut reflections);
    }
    assert_eq!(
        reflections, 1,
        "do not expand or duplicate the real source dispatch"
    );
    let original = emit_and_run::ruby()
        .args(["-e", &format!("{SOURCE}\nSourceComputedMetadata.exercise")])
        .output()
        .unwrap();
    let lowered = emit_and_run::ruby()
        .args([
            "-e",
            "require_relative 'app/models'; SourceComputedMetadata.exercise",
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
#[test]
fn unknown_values_overrides_and_unproved_inheritance_stay_open() {
    use roundhouse::ty::Ty;
    for (label, source) in [
        (
            "method_missing protocol",
            SOURCE.replace(
                "  def parse_line(line)",
                "  def method_missing(name, *args); nil; end\n  def parse_line(line)",
            ),
        ),
        (
            "unknown value",
            SOURCE.replace("value.join(\":\").strip", "unknown_value"),
        ),
        (
            "unproved selector suffix",
            SOURCE.replace("#{attribute}=", "#{attribute}"),
        ),
        (
            "own reflection override",
            SOURCE.replace(
                "  def parse_line(line)",
                "  def public_send(name, value); nil; end\n  def parse_line(line)",
            ),
        ),
        (
            "inherited reflection override",
            format!(
                "class WriterParent\n def public_send(name, value); nil; end\nend\n{}",
                SOURCE.replace(
                    "class SourceComputedMetadata",
                    "class SourceComputedMetadata < WriterParent"
                )
            ),
        ),
        (
            "indexed descendant",
            format!("{SOURCE}\nclass WriterChild < SourceComputedMetadata\nend\n"),
        ),
        (
            "implicit Object writer",
            format!("class Object\n def extra=(value); @name = 71; end\nend\n{SOURCE}"),
        ),
        (
            "declared gradual setter",
            SOURCE.replace(
                "  def name=(value)",
                "  #: (untyped value) -> untyped\n  def name=(value)",
            ),
        ),
    ] {
        let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let method = typed
            .library_classes
            .iter()
            .find(|c| c.name.0.as_str() == "SourceComputedMetadata")
            .unwrap()
            .methods
            .iter()
            .find(|m| m.name.as_str() == "name")
            .unwrap();
        assert!(
            method
                .signature
                .as_ref()
                .is_none_or(|sig| matches!(sig, Ty::Fn { ret, .. } if ret.mentions_unknown())),
            "{label}: {method:#?}"
        );
    }
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn computed_metadata_writers_preserve_native_values_conversion_and_effect_order() {
    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("probe.rb"),
        "require_relative 'app/models'; SourceComputedMetadata.exercise\n",
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
    assert_eq!(native.stdout, b"source computed metadata writer PASS\n");
}

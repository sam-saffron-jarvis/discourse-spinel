#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
const SOURCE: &str = r#"class StoredValue
  def initialize(value)
    @value = value
  end
  def value
    @value
  end
end
class AssignmentSetter
  attr_reader :seen
  def []=(key, value)
    @seen = value
    :setter_answer
  end
end
class IndexWriteProbe
  @events = []
  def self.table
    @events << :receiver
    @table ||= {}
  end
  def self.key
    @events << :key
    :entry
  end
  def self.value
    @events << :rhs
    StoredValue.new(7)
  end
  def self.store
    table[key] = value
  end
  def self.run
    returned = store
    raise "operand order/count" unless @events == [:receiver, :key, :rhs]
    raise "tail assignment identity" unless returned.equal?(table[:entry])
    raise "tail assignment value" unless returned.value == 7
    setter = AssignmentSetter.new
    object = StoredValue.new(9)
    assigned = (setter[:entry] = object)
    explicit = setter.[]=(:entry, object)
    raise "setter result replaced assignment RHS" unless assigned.equal?(object)
    raise "setter did not run" unless setter.seen.equal?(object)
    raise "explicit method call changed" unless explicit == :setter_answer
    target = {}.freeze
    begin
      target[:entry] = object
      raise "frozen write succeeded"
    rescue FrozenError
    end
    puts "indexed assignment return PASS"
  end
end
"#;
fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/index_write_probe.rb", SOURCE)
}
#[test]
fn indexed_assignment_and_explicit_setter_have_distinct_ir_and_rhs_contracts() {
    let (out, typed, errors) = app().emit_with_app(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let class = typed
        .library_classes
        .iter()
        .find(|c| c.name.0.as_str() == "IndexWriteProbe")
        .unwrap();
    let method = class
        .methods
        .iter()
        .find(|m| m.name.as_str() == "store")
        .unwrap();
    assert!(
        matches!(&*method.body.node,roundhouse::expr::ExprNode::Seq{exprs} if matches!(exprs.last().map(|e|&*e.node),Some(roundhouse::expr::ExprNode::Assign{target:roundhouse::expr::LValue::Index{..},..})))
            || matches!(
                &*method.body.node,
                roundhouse::expr::ExprNode::Assign {
                    target: roundhouse::expr::LValue::Index { .. },
                    ..
                }
            ),
        "{method:#?}"
    );
    assert!(
        matches!(method.body.ty.as_ref(),Some(roundhouse::ty::Ty::Class{id,..}) if id.0.as_str()=="StoredValue"),
        "{method:#?}"
    );
    let original = emit_and_run::ruby()
        .args(["-e", &format!("{SOURCE}\nIndexWriteProbe.run")])
        .output()
        .unwrap();
    let lowered = emit_and_run::ruby()
        .args(["-e", "require_relative 'app/models'; IndexWriteProbe.run"])
        .current_dir(&*out)
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
    assert_eq!(original.stdout, lowered.stdout);
}
#[test]
fn unsupported_index_assignment_shapes_do_not_become_explicit_setter_calls() {
    for source in [
        "target[first, second] = value",
        "target[*keys] = value",
        "target[first, *keys] = value",
    ] {
        let parsed = ruby_prism::parse(source.as_bytes());
        assert_eq!(parsed.errors().count(), 0, "legal Ruby control: {source}");
        let root = parsed.node();
        let statement = root
            .as_program_node()
            .unwrap()
            .statements()
            .body()
            .iter()
            .next()
            .unwrap();
        let result = roundhouse::ingest::ingest_expr(&statement, "<index-write>");
        assert!(
            matches!(result, Err(roundhouse::ingest::IngestError::Unsupported { ref message, .. })
            if message.contains("indexed assignment requires one non-variadic index and an RHS")),
            "{source}: {result:?}"
        );
    }
}

#[test]
fn indexed_write_expressions_reach_a_ruby_ir_fixed_point() {
    for source in [
        "target[key] = value",
        "target.[]=(key, value)",
        "target.[]=(first, second, value)",
    ] {
        let render = |source: &str| {
            let parsed = ruby_prism::parse(source.as_bytes());
            assert_eq!(parsed.errors().count(), 0, "{source}");
            let root = parsed.node();
            let statement = root
                .as_program_node()
                .unwrap()
                .statements()
                .body()
                .iter()
                .next()
                .unwrap();
            let expr = roundhouse::ingest::ingest_expr(&statement, "<index-write>").unwrap();
            roundhouse::emit::ruby::emit_expr(&expr)
        };
        let emitted = render(source);
        assert_eq!(render(&emitted), emitted, "{source}");
    }
}

#[test]
#[ignore = "requires Spinel; no services"]
fn native_tail_index_store_preserves_identity_errors_effects_and_setter_return_distinction() {
    let (out, errors) = app().emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        out.join("probe.rb"),
        "require_relative 'app/models'\nIndexWriteProbe.run\n",
    )
    .unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compiled = std::process::Command::new(compiler)
        .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(out.join("probe"))
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(native.stdout, b"indexed assignment return PASS\n");
}

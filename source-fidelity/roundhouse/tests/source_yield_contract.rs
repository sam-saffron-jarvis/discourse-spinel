//! Source yield -> callable argument contracts, reduced from YamlLoader#load.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r##"class SourceTupleLoader
  def load
    [:core, :extra].each do |category|
      yield category, :fixture, 17, {themeable: true}
    end
    nil
  end
end
class SourceTupleConsumer
  def self.exercise
    rows = []
    SourceTupleLoader.new.load do |category, name, default, opts|
      rows << "#{category}:#{name}:#{default}:#{opts[:themeable]}"
      :observed
    end
    raise "yield tuple/order" unless rows == ["core:fixture:17:true", "extra:fixture:17:true"]
    puts "source yield tuple PASS"
  end
end
"##;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/source_tuple_loader.rb", source)
}
#[test]
fn actual_source_yield_closes_callback_arguments_and_result() {
    let (emitted, typed, errors) =
        app(SOURCE).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let loader = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "SourceTupleLoader")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "load")
        .unwrap();
    let Some(roundhouse::ty::Ty::Fn {
        block: Some(block), ..
    }) = &loader.signature
    else {
        panic!("{loader:#?}")
    };
    let roundhouse::ty::Ty::Fn { params, ret, .. } = &**block else {
        panic!("{block:#?}")
    };
    assert!(
        !loader.effects.is_pure(),
        "a typed yield must not become a pure operation"
    );
    assert_eq!(params.len(), 4);
    assert_eq!(**ret, roundhouse::ty::Ty::Sym);
    assert!(
        params.iter().all(|param| !param.ty.mentions_unknown()),
        "{params:#?}"
    );
    fn closed(expr: &roundhouse::expr::Expr) {
        assert!(
            expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
            "{expr:#?}"
        );
        expr.node.for_each_child(&mut closed);
    }
    for class in typed
        .library_classes
        .iter()
        .filter(|class| class.name.0.as_str().starts_with("SourceTuple"))
    {
        for method in &class.methods {
            closed(&method.body);
        }
    }
    let original = emit_and_run::ruby()
        .args(["-e", &format!("{SOURCE}\nSourceTupleConsumer.exercise")])
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
            "require_relative 'app/models'; SourceTupleConsumer.exercise",
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
fn source_yield_contract_runs_natively() {
    let (emitted, errors) = app(SOURCE).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("tuple.rb"),
        "require_relative 'app/models'; SourceTupleConsumer.exercise\n",
    )
    .unwrap();
    let compiled =
        std::process::Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
            .args(["--jobs=4", "--rbs", ".", "tuple.rb", "-o", "tuple"])
            .current_dir(&*emitted)
            .output()
            .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    let native = std::process::Command::new(emitted.join("tuple"))
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(native.stdout, b"source yield tuple PASS\n");
}

#[test]
fn explicit_gradual_block_and_unknown_consumer_results_remain_authoritative() {
    use roundhouse::ty::Ty;
    let (_, typed, _) = app(SOURCE).write("sig/source_tuple_loader.rbs", "class SourceTupleLoader\n def load: () { (untyped, untyped, untyped, untyped) -> untyped } -> nil\nend\n").emit_with_app(roundhouse::project::BuildTarget::Spinel);
    let loader = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "SourceTupleLoader")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "load")
        .unwrap();
    assert!(
        matches!(&loader.signature, Some(Ty::Fn { block: Some(block), .. }) if matches!(&**block, Ty::Fn { params, ret, .. } if params.iter().all(|param| *param.ty == Ty::Untyped) && **ret == Ty::Untyped)),
        "{loader:#?}"
    );
    let source = format!(
        "{SOURCE}\nclass OtherYieldConsumer\n def self.consume\n  SourceTupleLoader.new.load {{ |a,b,c,d| unknown_callback_result }}\n end\nend\n"
    );
    let (_, typed, _) = app(&source).emit_with_app(roundhouse::project::BuildTarget::Spinel);
    let loader = typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "SourceTupleLoader")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.name.as_str() == "load")
        .unwrap();
    assert!(
        matches!(&loader.signature, Some(Ty::Fn { block: Some(block), .. }) if matches!(&**block, Ty::Fn { ret, .. } if ret.mentions_unknown())),
        "{loader:#?}"
    );
}

#[test]
fn reflective_consumers_cannot_borrow_another_blocks_return_contract() {
    use roundhouse::ty::Ty;
    for suffix in [
        "class OtherYieldConsumer\n def self.consume\n  SourceTupleLoader.new.public_send(:load) { |a,b,c,d| \"different result\" }\n end\nend\n",
        "class OtherYieldConsumer\n def self.escape\n  SourceTupleLoader.new.method(:load)\n end\nend\n",
    ] {
        let (_, typed, _) = app(&format!("{SOURCE}\n{suffix}"))
            .emit_with_app(roundhouse::project::BuildTarget::Spinel);
        let loader = typed
            .library_classes
            .iter()
            .find(|class| class.name.0.as_str() == "SourceTupleLoader")
            .unwrap()
            .methods
            .iter()
            .find(|method| method.name.as_str() == "load")
            .unwrap();
        assert!(
            matches!(&loader.signature, Some(Ty::Fn { block: Some(block), .. }) if matches!(&**block, Ty::Fn { ret, .. } if ret.mentions_unknown())),
            "{loader:#?}"
        );
    }
}

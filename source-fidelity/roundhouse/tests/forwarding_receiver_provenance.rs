//! Source construction provenance design control for the real multisite
//! `.instance` destination boundary. These are compiler fixtures, NOT provider
//! implementations or a native core admission. A return type is not a source
//! construction/dispatch witness; explicit class-object meta types survive.
use roundhouse::analyze::{Analyzer, diagnose};
use roundhouse::diagnostic::DiagnosticKind;
use roundhouse::dialect::MethodReceiver;
use roundhouse::ingest::ingest_app_from_tree;
use roundhouse::ty::Ty;
use std::collections::HashMap;
use std::path::PathBuf;

const SOURCE: &str = r#"class ValueOriginWitness
  def target(value)
    value + 1
  end
  def self.target(value, extra)
    value + extra
  end
  def self.produce
    SOURCE_PRODUCER
  end
  def self.forward(...)
    value = SOURCE_BINDING
    value.target(...)
  end
end
"#;

fn analyzed(producer: &str, binding: &str) -> roundhouse::App {
    let source = SOURCE
        .replace("SOURCE_PRODUCER", producer)
        .replace("SOURCE_BINDING", binding);
    let mut app = ingest_app_from_tree(HashMap::from([(
        PathBuf::from("app/lib/value_origin.rb"),
        source.into_bytes(),
    )]))
    .unwrap();
    Analyzer::new(&app).analyze(&mut app);
    app
}

fn producer_result(app: &roundhouse::App) -> Ty {
    let producer = app
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "ValueOriginWitness")
        .unwrap()
        .methods
        .iter()
        .find(|method| method.receiver == MethodReceiver::Class && method.name.as_str() == "produce")
        .unwrap();
    let Some(Ty::Fn { ret, .. }) = &producer.signature else {
        panic!("source producer signature missing: {producer:#?}");
    };
    (**ret).clone()
}

fn forwarding_errors(app: &roundhouse::App) -> Vec<String> {
    diagnose(app).into_iter().filter_map(|diagnostic| {
        matches!(&diagnostic.kind, DiagnosticKind::Unsupported { construct, .. } if construct.as_str() == "full argument forwarding")
            .then_some(diagnostic.message)
    }).collect()
}

#[test]
fn source_factory_meta_types_do_not_replace_a_constructor_witness() {
    let instance = analyzed("new", "produce");
    let class_object = analyzed("self", "produce");
    let instance_ty = producer_result(&instance);
    let class_ty = producer_result(&class_object);
    // The initial nominal-conflation hypothesis was FALSE for these return
    // signatures: the analyzer already preserves SelfInstance / Class[T].
    // That still does not certify source dispatch/writers or the carrier.
    assert_eq!(instance_ty, Ty::SelfInstance);
    let explicit_instance_ty = producer_result(&analyzed("ValueOriginWitness.new", "produce"));
    let explicit_class_ty = producer_result(&analyzed("ValueOriginWitness", "produce"));
    assert!(matches!(&explicit_instance_ty, Ty::Class { id, args }
        if id.0.as_str() == "ValueOriginWitness" && args.is_empty()));
    assert_eq!(explicit_class_ty, class_ty);
    assert!(matches!(&class_ty, Ty::Class { id, args } if id.0.as_str() == "Class"
        && matches!(args.first(), Some(Ty::Class { id, .. }) if id.0.as_str() == "ValueOriginWitness")));
    for app in [&instance, &class_object] {
        let errors = forwarding_errors(app);
        assert!(
            errors
                .iter()
                .any(|error| error.contains("destination's declaration cannot be verified")),
            "borrowed inferred Class type admitted a factory: {errors:#?}"
        );
    }
    let execute = |producer: &str| {
        let source = SOURCE
            .replace("SOURCE_PRODUCER", producer)
            .replace("SOURCE_BINDING", "produce");
        let output = std::process::Command::new("ruby").arg("-e").arg(format!("{source}\nbegin\n p ValueOriginWitness.forward(7)\nrescue ArgumentError => error\n puts error.message\nend\n")).output().unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        output.stdout
    };
    assert_eq!(execute("new"), b"8\n");
    assert_eq!(execute("self"), b"wrong number of arguments (given 1, expected 2)\n");
}

#[test]
fn literal_construction_witness_verifies_source_destination_but_not_native_carrier() {
    let app = analyzed("new", "ValueOriginWitness.new");
    assert!(
        forwarding_errors(&app).is_empty(),
        "actual literal constructor witness lost: {:#?}",
        forwarding_errors(&app)
    );
    let (_, diagnostics) = roundhouse::emit::diagnostics::scope(|| {
        roundhouse::project::target_files(
            &app,
            roundhouse::fixtures::real_blog(),
            roundhouse::project::BuildTarget::Spinel,
        )
    });
    assert!(
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic.message.contains("full argument forwarding")),
        "a destination proof silently granted an unverified native carrier"
    );
}

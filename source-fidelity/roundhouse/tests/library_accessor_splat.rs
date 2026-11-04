use roundhouse::expr::{ExprNode, LValue};
use roundhouse::ingest::ingest_app_from_tree;

fn class(source: &str) -> roundhouse::dialect::LibraryClass {
    let app = ingest_app_from_tree(
        vec![(
            std::path::PathBuf::from("lib/plugin/metadata.rb"),
            source.as_bytes().to_vec(),
        )]
        .into_iter()
        .collect(),
    )
    .expect("ingest app");
    app.library_classes
        .into_iter()
        .find(|class| class.name.0.as_str() == "Plugin::Metadata")
        .expect("Plugin::Metadata ingested")
}

fn reduced_metadata(body: &str) -> String {
    format!("module Plugin\n  class Metadata\n{body}  end\nend\n")
}

#[test]
fn constant_splat_accessor_matches_direct_symbol_and_string_accessors() {
    let expanded = class(&reduced_metadata(
        "    FIELDS = %i[name status]\n    attr_accessor(*FIELDS)\n",
    ));
    let direct = class(&reduced_metadata("    attr_accessor :name, \"status\"\n"));

    let projection = |class: &roundhouse::dialect::LibraryClass| {
        class
            .methods
            .iter()
            .map(|method| {
                (
                    method.name.clone(),
                    method.receiver,
                    method.params.clone(),
                    method.body.clone(),
                )
            })
            .collect::<Vec<_>>()
    };
    assert_eq!(projection(&expanded), projection(&direct));

    for setter in ["name=", "status="] {
        let method = expanded
            .methods
            .iter()
            .find(|method| method.name.as_str() == setter)
            .unwrap();
        let ExprNode::Assign {
            target: LValue::Ivar { name },
            value,
        } = &*method.body.node
        else {
            panic!(
                "{setter} must assign its actual argument directly: {:?}",
                method.body.node
            );
        };
        assert_eq!(name.as_str(), setter.trim_end_matches('='));
        assert!(matches!(&*value.node, ExprNode::Var { name, .. } if name.as_str() == "value"));
    }
}

#[test]
fn unsupported_or_ambiguous_splats_remain_as_original_unknown_calls() {
    let cases = [
        // Forward constant references are not visible at this call site.
        "    attr_accessor(*FIELDS)\n    FIELDS = %i[name status]\n",
        // A later mutation taints the whole-body constant fact.
        "    FIELDS = %i[name status]\n    attr_accessor(*FIELDS)\n    FIELDS << :extra\n",
        // Aliases and subsequent writes are conservatively tainted.
        "    FIELDS = %i[name status]\n    ALIAS = FIELDS\n    ALIAS << :extra\n    attr_accessor(*FIELDS)\n",
        // The entire call declines rather than keeping the known prefix.
        "    FIELDS = %i[name status]\n    attr_accessor(:safe, *FIELDS, Object.new)\n",
        // Names that cannot safely map to ordinary instance variables decline.
        "    FIELDS = [:name, :\"not-safe?\"]\n    attr_accessor(*FIELDS)\n",
    ];

    for body in cases {
        let ingested = class(&reduced_metadata(body));
        assert!(
            ingested.methods.is_empty(),
            "must not synthesize a partial accessor set: {body}"
        );
        assert!(
            ingested.unknown_calls.iter().any(|expr| {
                matches!(&*expr.node, ExprNode::Send { method, .. } if method.as_str() == "attr_accessor")
            }),
            "original accessor call must remain represented: {body}"
        );
    }
}

#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const EXECUTABLE: &str = r#"class AccessorMetadata
  FIELDS = %i[name version].freeze
  attr_accessor(*FIELDS)
  def initialize
    @name = "initial"
    @version = "1"
  end
  def self.exercise
    metadata = new
    metadata.public_send(:name=, "source value")
    metadata.public_send(:version=, "2")
    raise "source accessor name" unless metadata.name == "source value"
    raise "source accessor version" unless metadata.version == "2"
    puts "source finite accessor PASS"
  end
end
"#;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/accessor_metadata.rb", EXECUTABLE)
}

#[test]
fn reduced_metadata_accessors_preserve_original_and_lowered_values() {
    let (emitted, typed, errors) = app().emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    fn closed(expr: &roundhouse::expr::Expr) {
        assert!(
            expr.ty.as_ref().is_some_and(|ty| !ty.mentions_unknown()),
            "{expr:#?}"
        );
        expr.node.for_each_child(&mut closed);
    }
    for method in &typed
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "AccessorMetadata")
        .unwrap()
        .methods
    {
        closed(&method.body);
    }
    let original = emit_and_run::ruby()
        .args(["-e", &format!("{EXECUTABLE}\nAccessorMetadata.exercise")])
        .output()
        .unwrap();
    let lowered = emit_and_run::ruby()
        .args([
            "-e",
            "require_relative 'app/models'; AccessorMetadata.exercise",
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
#[ignore = "requires Spinel; no external services"]
fn reduced_metadata_accessors_run_natively() {
    let (emitted, errors) = app().emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(
        emitted.join("probe.rb"),
        "require_relative 'app/models'; AccessorMetadata.exercise\n",
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
    assert_eq!(native.stdout, b"source finite accessor PASS\n");
}

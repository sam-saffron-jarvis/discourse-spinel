#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
const SOURCE: &str = r#"class ReaderProducer
  %i[entries assets].each do |att|
    class_eval %Q{
      def #{att}
        @#{att} ||= []
      end
    }
  end
end
"#;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/reader_producer.rb", source)
}
const OBSERVE: &str = r#"a=ReaderProducer.new
b=ReaderProducer.new
first=a.entries
a.entries << :one
raise "memo identity" unless first.equal?(a.entries)
raise "per-instance storage" unless b.entries.empty?
raise "separate slots" unless a.assets.empty?
a.instance_variable_set(:@assets, false)
raise "false fallback" unless a.assets == []
raise "false fallback memo" unless a.assets.equal?(a.assets)
puts "native reader producer PASS"
"#;
#[test]
fn native_preserves_the_source_declaration_instead_of_inventing_accessors() {
    let (out, errors) = app(SOURCE).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let text = std::fs::read_to_string(out.join("app/models/reader_producer.rb")).unwrap();
    assert!(
        text.contains("class_eval") && text.contains("#{att}") && text.contains("||= []"),
        "{text}"
    );
    let original = emit_and_run::ruby()
        .args(["-e", &format!("{SOURCE}\n{OBSERVE}")])
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let lowered = emit_and_run::ruby()
        .args(["-e", &format!("require_relative 'app/models';\n{OBSERVE}")])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        lowered.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(original.stdout, lowered.stdout);
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn exact_reader_producer_runs_natively_with_late_false_and_instance_aliases() {
    let (out, errors) = app(SOURCE).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    std::fs::write(
        out.join("probe.rb"),
        format!("require_relative 'app/models'\n{OBSERVE}"),
    )
    .unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let build = std::process::Command::new(compiler)
        .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        build.status.success(),
        "{}",
        String::from_utf8_lossy(&build.stderr)
    );
    let native = std::process::Command::new(out.join("probe"))
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    assert_eq!(native.stdout, b"native reader producer PASS\n");
}
#[test]
fn dynamic_templates_extra_effects_hooks_inheritance_and_typed_writer_worlds_stay_unadmitted() {
    for source in [
        SOURCE.replace("%i[entries assets]", "runtime_names"),
        SOURCE.replace("@#{att} ||= []", "@#{att} ||= build_entries"),
        SOURCE.replace("@#{att} ||= []", "@#{att} ||= []; record_effect"),
        SOURCE.replace("def #{att}", "private; def #{att}"),
        SOURCE.replace("end\n    }", "end; private :#{att}\n    }"),
        SOURCE.replace("class ReaderProducer", "class ReaderProducer < OtherBase"),
        SOURCE.replace(
            "class ReaderProducer\n",
            "class ReaderProducer\n  def self.class_eval(value); value; end\n",
        ),
        SOURCE.replace(
            "class ReaderProducer\n",
            "class ReaderProducer\n  def self.method_added(name); log(name); end\n",
        ),
        SOURCE.replace(
            "class ReaderProducer\n",
            "class ReaderProducer\n  def reset; @entries = false; end\n",
        ),
        SOURCE.replace(
            "class ReaderProducer\n",
            "class ReaderProducer\n  def entries; 7; end\n",
        ),
    ] {
        let (_, typed, _) = app(&source).emit_with_app(BuildTarget::Spinel);
        let class = typed
            .library_classes
            .iter()
            .find(|c| c.name.0.as_str() == "ReaderProducer")
            .unwrap();
        assert!(
            class
                .unknown_calls
                .iter()
                .all(|e| e.decisions & roundhouse::expr::REPLAYED_CLASS_BODY == 0),
            "unproved producer admitted: {class:#?}"
        );
    }
}

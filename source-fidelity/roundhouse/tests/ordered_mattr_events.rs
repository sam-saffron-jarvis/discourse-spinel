//! Plain ordered mattr events: actual storage protocol, paired public methods.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

use roundhouse::project::BuildTarget;

const SOURCE: &str = r#"module OrderedMattr
  EVENTS = []
  def self.class_variable_set(name, value)
    EVENTS << "storage:#{name}"
    if name == "@@first"
      @@first = value
    else
      @@second = value
    end
  end
  def self.singleton_method_added(name)
    return if name == :singleton_method_added || name == :method_added
    EVENTS << "class:#{name}:#{class_variable_defined?(:@@first)}:#{class_variable_defined?(:@@second)}"
  end
  def self.method_added(name)
    EVENTS << "instance:#{name}:#{class_variable_defined?(:@@first)}:#{class_variable_defined?(:@@second)}"
  end
  private
  mattr_accessor :first, :second
  @@first = ["live"]
  @@second = ["second"]
end
class OrderedMattrInstance
  include OrderedMattr
end
"#;

const PROBE: &str = r#"
expected = ["storage:@@first", "storage:@@second",
  "class:first:true:true", "instance:first:true:true",
  "class:second:true:true", "instance:second:true:true",
  "class:first=:true:true", "instance:first=:true:true",
  "class:second=:true:true", "instance:second=:true:true"]
raise "storage/definition protocol order" unless OrderedMattr::EVENTS == expected
raise "later source initialization" unless OrderedMattr.first == ["live"]
raise "second field" unless OrderedMattr.second == ["second"]
instance = OrderedMattrInstance.new
raise "instance/class alias identity" unless instance.first.equal?(OrderedMattr.first)
instance.first << "instance"
raise "shared storage" unless OrderedMattr.first == ["live", "instance"]
instance.second = ["writer"]
raise "instance writer" unless OrderedMattr.second == ["writer"]
raise "class public" unless OrderedMattr.respond_to?(:first) && OrderedMattr.respond_to?(:first=)
raise "instance public" unless instance.respond_to?(:first) && instance.respond_to?(:first=)
puts "ordered mattr protocol and both method sides PASS"
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/ordered_mattr.rb", source)
}

fn original(source: &str, probe: &str) -> std::process::Output {
    emit_and_run::ruby()
        .args([
            "--enable-frozen-string-literal",
            "-ractive_support/core_ext/module/attribute_accessors",
            "-e",
        ])
        .arg(format!("require 'digest'\nmacro_source = Module.instance_method(:mattr_accessor).source_location.first\nraise 'original macro source changed' unless Digest::SHA256.file(macro_source).hexdigest == '2d138af1438e8f9091d8ec9e0ed350c067be4748c887cd70cd28fecafaceba60'\n{source}\n{probe}"))
        .output()
        .unwrap()
}

#[test]
fn real_protocol_seeds_precede_paired_public_definitions() {
    let oracle = original(SOURCE, PROBE);
    assert!(oracle.status.success(), "{}", String::from_utf8_lossy(&oracle.stderr));
    let (emitted, errors) = app(SOURCE).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let lowered = emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models'\n{PROBE}"))
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        lowered.status.success(),
        "{}\n{}",
        emitted.display(),
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(oracle.stdout, lowered.stdout);
}

fn repeated_case() -> (String, &'static str) {
    let source = SOURCE.replace(
        "  @@first = [\"live\"]",
        "  @@first = [\"live\"]\n  mattr_accessor :first",
    );
    let probe = r#"
raise "nil redeclaration reset value" unless OrderedMattr.first == ["live"]
raise "reader hooks deduplicated" unless OrderedMattr::EVENTS.count("class:first:true:true") == 2 && OrderedMattr::EVENTS.count("instance:first:true:true") == 2
raise "writer hooks deduplicated" unless OrderedMattr::EVENTS.count("class:first=:true:true") == 2 && OrderedMattr::EVENTS.count("instance:first=:true:true") == 2
raise "nil redeclaration repeated storage" unless OrderedMattr::EVENTS.count("storage:@@first") == 1
raise "repeated event order" unless OrderedMattr::EVENTS.last(4) == ["class:first:true:true", "instance:first:true:true", "class:first=:true:true", "instance:first=:true:true"]
instance = OrderedMattrInstance.new
raise "reinstalled sides lost identity" unless instance.first.equal?(OrderedMattr.first)
replacement = ["replacement"]
instance.first = replacement
raise "reinstalled instance writer" unless OrderedMattr.first.equal?(replacement)
OrderedMattr.first = ["class writer"]
instance.first << "still shared"
raise "reinstalled class writer" unless OrderedMattr.first == ["class writer", "still shared"]
raise "reinstalled public methods" unless OrderedMattr.respond_to?(:first) && OrderedMattr.respond_to?(:first=) && instance.respond_to?(:first) && instance.respond_to?(:first=)
puts "repeated definition events PASS"
"#;
    (source, probe)
}

#[test]
fn repeated_plain_declarations_keep_both_definition_events_under_cruby() {
    let (source, probe) = repeated_case();
    let oracle = original(&source, probe);
    assert!(oracle.status.success(), "{}", String::from_utf8_lossy(&oracle.stderr));
    app(&source).run_ruby(probe).assert_passes();
}

#[test]
#[ignore = "requires Spinel; no external service"]
fn native_identical_accessor_reinstallation_keeps_all_real_hooks() {
    let (source, probe) = repeated_case();
    app(&source).run_spinel_with_rbs(probe).assert_passes();
}

#[test]
#[ignore = "requires Spinel and original ActiveSupport; no external service"]
fn plain_ordered_protocol_runs_natively() {
    app(SOURCE).run_spinel_with_rbs(PROBE).assert_passes();
}

#[test]
fn macro_and_core_override_worlds_do_not_use_the_standard_expansion() {
    for source in [
        SOURCE.replace(
            "  private",
            "  def self.mattr_reader(*names)\n    nil\n  end\n  private",
        ),
        format!("class String\n  def +@\n    'changed'\n  end\nend\n{SOURCE}"),
    ] {
        let tree = [
            (
                std::path::PathBuf::from("config/routes.rb"),
                b"Rails.application.routes.draw do\nend\n".to_vec(),
            ),
            (
                std::path::PathBuf::from("lib/ordered_mattr.rb"),
                source.as_bytes().to_vec(),
            ),
        ]
        .into_iter()
        .collect();
        let (result, _) = roundhouse::ingest::prism::scope(|| roundhouse::ingest::ingest_app_from_tree(tree));
        let error = result.err().expect("changed macro/core world must refuse").to_string();
        assert!(error.contains("ordered plain mattr requires"), "{error}");
    }
}

const NONWRITING_SOURCE: &str = r#"module NonwritingMattr
  def self.class_variable_set(name, value)
    value
  end
  mattr_accessor :value
end
"#;
const NONWRITING_PROBE: &str = r#"
raise "invented assigned storage" if NonwritingMattr.class_variable_defined?(:@@value)
begin
  NonwritingMattr.value
  raise "reader returned invented nil"
rescue NameError
  puts "actual nonwriting storage override PASS"
end
"#;

#[test]
fn a_nonwriting_storage_override_does_not_get_a_synthetic_assignment() {
    let oracle = original(NONWRITING_SOURCE, NONWRITING_PROBE);
    assert!(oracle.status.success(), "{}", String::from_utf8_lossy(&oracle.stderr));
    app(NONWRITING_SOURCE).run_ruby(NONWRITING_PROBE).assert_passes();
}

#[test]
#[ignore = "requires Spinel; no external service"]
fn native_nonwriting_storage_override_does_not_get_an_assigned_slot() {
    app(NONWRITING_SOURCE)
        .run_spinel_with_rbs(NONWRITING_PROBE)
        .assert_passes();
}

const KEYWORD_SOURCE: &str = r#"module KeywordMattrCapture
  EVENTS = []
  @evaluations = 0
  def self.argument
    @evaluations += 1
    []
  end
  def self.evaluations
    @evaluations
  end
  def self.class_variable_set(name, value)
    EVENTS << value
    @@value = value
  end
  def self.singleton_method_added(name)
    if name == :value
      @@value = ["changed by real definition hook"]
    end
  end
  mattr_accessor :value, default: argument
end
"#;
const KEYWORD_PROBE: &str = r#"
raise "argument evaluated twice" unless KeywordMattrCapture.evaluations == 1
raise "reader/writer storage protocol" unless KeywordMattrCapture::EVENTS.length == 2
raise "default argument identity changed" unless KeywordMattrCapture::EVENTS[0].equal?(KeywordMattrCapture::EVENTS[1])
raise "stored value not captured argument" unless KeywordMattrCapture.value.equal?(KeywordMattrCapture::EVENTS[0])
KeywordMattrCapture.value << "live"
raise "capture was a snapshot" unless KeywordMattrCapture::EVENTS[1] == ["live"]
puts "keyword argument capture PASS"
"#;

#[test]
fn a_keyword_argument_is_evaluated_once_and_shared_across_both_phases() {
    let oracle = original(KEYWORD_SOURCE, KEYWORD_PROBE);
    assert!(oracle.status.success(), "{}", String::from_utf8_lossy(&oracle.stderr));
    app(KEYWORD_SOURCE).run_ruby(KEYWORD_PROBE).assert_passes();
}

#[test]
#[ignore = "requires Spinel; no external service"]
fn native_keyword_argument_keeps_evaluation_and_mutable_identity() {
    app(KEYWORD_SOURCE).run_spinel_with_rbs(KEYWORD_PROBE).assert_passes();
}

#[test]
fn a_capture_does_not_claim_unproved_local_or_method_surface_reflection() {
    for source in [
        KEYWORD_SOURCE.replace(
            "    @evaluations += 1",
            "    respond_to?(:value)\n    @evaluations += 1",
        ),
        KEYWORD_SOURCE.replace("    @evaluations += 1", "    local_variables\n    @evaluations += 1"),
    ] {
        let tree = [(std::path::PathBuf::from("lib/ordered_mattr.rb"), source.into_bytes())]
            .into_iter()
            .collect();
        let (result, diagnostics) = roundhouse::ingest::prism::scope(|| roundhouse::ingest::ingest_app_from_tree(tree));
        let mut messages: Vec<_> = diagnostics
            .iter()
            .map(|diagnostic| diagnostic.message.clone())
            .collect();
        if let Err(error) = result {
            messages.push(error.to_string());
        }
        assert!(
            messages
                .iter()
                .any(|message| message.contains("unmodified macro/core protocol")),
            "{messages:#?}"
        );
    }
}

#[test]
fn a_module_block_default_keeps_the_measured_timing_refusal() {
    let source = "module UnprovedBlockDefault\n  mattr_accessor(:value) { respond_to?(:value) }\nend\n";
    let errors = app(source).check_errors();
    assert!(
        errors
            .iter()
            .any(|error| error
                .contains("block defaults require a preserved block frame and method-surface timing proof")),
        "{errors:#?}"
    );
}

#[test]
fn a_keyword_capture_local_is_hygienic_against_the_actual_source_parse() {
    let template = "module CaptureNameHygiene\n  def self.reserve(RESERVED)\n    nil\n  end\n  mattr_accessor :value, default: []\nend\n";
    let mut reserved = String::from("__rh_mattr_argument_0");
    let source = loop {
        let source = template.replace("RESERVED", &reserved);
        let at = source.find("mattr_accessor").unwrap();
        let candidate = format!("__rh_mattr_argument_{at}");
        if candidate == reserved {
            break source;
        }
        reserved = candidate;
    };
    let classes = roundhouse::ingest::ingest_library_classes(source.as_bytes(), "keyword_capture_hygiene.rb").unwrap();
    let temporary = classes[0]
        .class_ivar_initializers
        .iter()
        .find_map(|expr| match &*expr.node {
            roundhouse::expr::ExprNode::Assign {
                target: roundhouse::expr::LValue::Var { name, .. },
                ..
            } if !name.as_str().starts_with('@') => Some(name.as_str()),
            _ => None,
        })
        .expect("once-only local argument event");
    assert_ne!(temporary, reserved);
    assert!(temporary.starts_with(&reserved));
}

#[test]
fn repeated_accessors_do_not_admit_method_object_or_surface_observation() {
    let (source, _) = repeated_case();
    let source = source.replace("  private", "  def self.observe_method\n    method(:first)\n  end\n  private");
    let tree = [(std::path::PathBuf::from("lib/ordered_mattr.rb"), source.into_bytes())].into_iter().collect();
    let (result, diagnostics) = roundhouse::ingest::prism::scope(|| roundhouse::ingest::ingest_app_from_tree(tree));
    let mut messages: Vec<_> = diagnostics.iter().map(|diagnostic| diagnostic.message.clone()).collect();
    if let Err(error) = result { messages.push(error.to_string()); }
    assert!(messages.iter().any(|message| message.contains("unmodified macro/core protocol")), "{messages:#?}");
}

#[test]
fn a_changed_source_body_does_not_use_the_identical_accessor_proof() {
    let source = SOURCE.replace("  private", "  def self.first\n    ['old body']\n  end\n  private");
    let mut app = roundhouse::App::default();
    app.library_classes = roundhouse::ingest::ingest_library_classes(source.as_bytes(), "changed_accessor_body.rb").unwrap();
    let error = roundhouse::project::target_files(&app, std::path::Path::new("."), BuildTarget::Spinel).unwrap_err();
    assert!(error.contains("method redefinition is not supported"), "{error}");
}

fn ingested(source: &str) -> roundhouse::App {
    let tree = [(std::path::PathBuf::from("lib/ordered_mattr.rb"), source.as_bytes().to_vec())].into_iter().collect();
    let (result, diagnostics) = roundhouse::ingest::prism::scope(|| roundhouse::ingest::ingest_app_from_tree(tree));
    assert!(diagnostics.is_empty(), "{diagnostics:#?}");
    result.unwrap()
}

#[test]
fn repeated_events_refuse_core_reopen_ancestor_and_early_observation_worlds() {
    let (source, _) = repeated_case();
    let mut cases = vec![
        format!("{source}\nmodule OrderedMattr\n  def self.late; nil; end\nend\n"),
        format!("class Module\n  def class_variable_defined?(name); false; end\nend\n{source}"),
        format!("class NilClass\n  def nil?; false; end\nend\n{source}"),
    ];
    for observation in ["method(:first)", "singleton_method(:first)", "instance_method(:first)",
        "method_defined?(:first)", "public_method_defined?(:first)", "respond_to?(:first)",
        "singleton_methods", "instance_methods", "defined?(self.first)", "self.first", "self.second=(nil)"] {
        cases.push(source.replace("  private", &format!("  def self.observe\n    {observation}\n  end\n  private")));
    }
    for source in cases {
        let tree = [(std::path::PathBuf::from("lib/ordered_mattr.rb"), source.clone().into_bytes())].into_iter().collect();
        let (result, diagnostics) = roundhouse::ingest::prism::scope(|| roundhouse::ingest::ingest_app_from_tree(tree));
        let refused = result.is_err() || diagnostics.iter().any(|d| d.severity == roundhouse::diagnostic::Severity::Error);
        // A source include can be folded out before validation; emit still checks provenance.
        if !refused {
            let error = roundhouse::project::target_files(&result.unwrap(), std::path::Path::new("."), BuildTarget::Spinel).err().unwrap_or_else(|| panic!("unexpected admission: {source}"));
            assert!(error.contains("method redefinition is not supported"), "{error}\n{source}");
        }
    }
}

#[test]
fn identical_shape_requires_actual_module_call_and_exact_event_provenance_at_emit() {
    let (source, _) = repeated_case();
    let app = ingested(&source);
    for change in 0..11 {
        let mut app = app.clone();
        let owner_index = app.library_classes.iter().position(|lc| lc.name.0.as_str() == "OrderedMattr").unwrap();
        let owner = &mut app.library_classes[owner_index];
        let method_index = owner.methods.iter().rposition(|method| method.name.as_str() == "first" && method.receiver == roundhouse::dialect::MethodReceiver::Class).unwrap();
        match change {
            0 => app.sources.clear(),
            1 => { let method = &mut owner.methods[method_index]; method.body.set_declaration_step(roundhouse::expr::DeclarationStep { call: roundhouse::span::Span::synthetic(), ordinal: 2 }); }
            2 => { let method = &mut owner.methods[method_index]; let mut step = method.body.declaration_step().unwrap(); step.ordinal += 1; method.body.set_declaration_step(step); }
            3 => { let method = &mut owner.methods[method_index]; method.enclosing_class = Some("WrongOwner".into()); }
            4 => { let method = &mut owner.methods[method_index]; method.name_span = roundhouse::span::Span::synthetic(); }
            5 => { for file in &mut app.sources { file.text = file.text.replace("module OrderedMattr", "module DifferentOwner"); } }
            6 => { let mut reopen = owner.clone(); reopen.methods.clear(); reopen.class_ivar_initializers.clear(); app.library_classes.push(reopen); }
            7 => { app.library_classes.extend(roundhouse::ingest::ingest_library_classes(b"class Module\n def class_variable_set(name, value); value; end\nend", "changed_core.rb").unwrap()); }
            8 => owner.is_module = false,
            9 => { for file in &mut app.sources { file.text = file.text.replace("  @@second = [\"second\"]", "  @@second = [\"second\"]\n  include OtherAncestor"); } }
            10 => owner.includes.push(roundhouse::ClassId("OtherAncestor".into())),
            _ => unreachable!(),
        }
        let error = roundhouse::project::target_files(&app, std::path::Path::new("."), BuildTarget::Spinel).unwrap_err();
        assert!(error.contains("method redefinition is not supported"), "case {change}: {error}");
    }
}

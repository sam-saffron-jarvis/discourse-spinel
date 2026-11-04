//! Runtime declaration captures must retain identity and run at the call,
//! not at the source offset of the macro's definition. No external services.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const STRINGS: &str = r#"class CapturedStrings
  def self.declare
    first = :same.to_s
    alias_value = first
    second = :same.to_s
    define_singleton_method(:first) { first }
    define_singleton_method(:alias_value) { alias_value }
    define_singleton_method(:second) { second }
    [:left, :right].each do |name|
      value = :same.to_s
      define_singleton_method(name) { value }
    end
  end
  declare
end
"#;
const STRING_PROBE: &str = r#"
raise "captured alias lost" unless CapturedStrings.first.equal?(CapturedStrings.alias_value)
raise "equal text is not object identity" if CapturedStrings.first.equal?(CapturedStrings.second)
raise "loop evaluations were merged" if CapturedStrings.left.equal?(CapturedStrings.right)
CapturedStrings.first << "!"
raise "capture was recreated" unless CapturedStrings.alias_value == "same!"
raise "independent capture mutated" unless CapturedStrings.second == "same" && CapturedStrings.left == "same"
puts "capture identity PASS"
"#;
const ORDER: &str = r#"class CaptureOrder
  @reads = 0
  @phase = :initial
  def self.declare(name)
    value = phase
    define_singleton_method(name) { value }
  end
  def self.phase
    @reads += 1
    @phase
  end
  def self.read_count
    @reads
  end
  @phase = :first
  declare :first
  @phase = :second
  declare :second
  @phase = :finished
end
"#;
const ORDER_PROBE: &str = r#"
raise "first capture evaluated out of order" unless CaptureOrder.first == :first
raise "second capture evaluated out of order" unless CaptureOrder.second == :second
CaptureOrder.first
CaptureOrder.second
raise "capture must evaluate exactly once at each call" unless CaptureOrder.read_count == 2
raise "class state changed" unless CaptureOrder.phase == :finished
puts "capture order PASS"
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/captured_values.rb", source)
}

fn original_ruby(source: &str, probe: &str) {
    let output = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{source}\n{probe}")).output().expect("run original Ruby");
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
}

fn lowered_ruby(source: &str, probe: &str) {
    let (emitted, errors) = app(source).emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let file = if source == STRINGS { "captured_strings" } else { "capture_order" };
    let output = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/{file}'\n{probe}"))
        .current_dir(&*emitted).output().expect("run same lowered Ruby");
    assert!(output.status.success(), "{}\n{}\n{}", emitted.display(),
        String::from_utf8_lossy(&output.stdout), String::from_utf8_lossy(&output.stderr));
}

#[test]
fn strings_preserve_aliases_without_merging_distinct_evaluations() {
    original_ruby(STRINGS, STRING_PROBE);
    lowered_ruby(STRINGS, STRING_PROBE);
    app(STRINGS).run_ruby(STRING_PROBE).assert_passes();
}

#[test]
fn runtime_values_are_captured_at_each_declaration_call() {
    original_ruby(ORDER, ORDER_PROBE);
    lowered_ruby(ORDER, ORDER_PROBE);
    app(ORDER).run_ruby(ORDER_PROBE).assert_passes();
}

#[test]
fn model_owned_runtime_declarations_remain_refused() {
    let model = ORDER.replace("class CaptureOrder", "class CaptureOrder < ActiveRecord::Base");
    let overlay = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("app/models/capture_order.rb", &model);
    let (_, errors) = overlay.emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.iter().any(|error| error.contains("runtime-defined method not supported")), "{errors:#?}");
}

#[test]
fn targets_without_ordered_class_execution_refuse_runtime_captures() {
    let (_, errors) = app(STRINGS).emit(roundhouse::project::BuildTarget::Go);
    assert!(errors.iter().any(|error| error.contains("initializes declaration captures in class-body execution order")), "{errors:#?}");
}

#[test]
fn declaration_order_retains_original_definer_spans() {
    let macro_body = "  def self.declare(name)\n    value = phase\n    define_singleton_method(name) { value }\n  end\n";
    let parent = format!("class CaptureBase\n{macro_body}end\n");
    let child = ORDER.replace("class CaptureOrder", "class CaptureOrder < CaptureBase").replace(macro_body, "");
    let overlay = app(&child).write("lib/capture_base.rb", &parent);
    let (emitted, lowered, errors) = overlay.emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let class = lowered.library_classes.iter().find(|class| class.name.0.as_str() == "CaptureOrder").unwrap();
    let (_, value) = class.constants.iter().find(|(name, _)| name.as_str().starts_with("ROUNDHOUSE_MACRO_")).unwrap();
    let step = value.declaration_step().expect("explicit declaration execution site");
    assert_ne!(value.span.file, step.call.file, "definer provenance was overwritten");
    assert!(lowered.sources[(value.span.file.0 - 1) as usize].path.ends_with("capture_base.rb"));
    assert!(lowered.sources[(step.call.file.0 - 1) as usize].path.ends_with("captured_values.rb"));
    let output = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("require_relative 'app/models/capture_order'\n{ORDER_PROBE}"))
        .current_dir(&*emitted).output().expect("run inherited declaration");
    assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn capture_identity_and_declaration_order_run_natively() {
    app(STRINGS).run_spinel_with_rbs(STRING_PROBE).assert_passes();
    app(ORDER).run_spinel_with_rbs(ORDER_PROBE).assert_passes();
}

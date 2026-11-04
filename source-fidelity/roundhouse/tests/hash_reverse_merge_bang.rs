#[path = "support/emit_and_run.rs"]
mod emit_and_run;
const SOURCE: &str = r#"class ReverseOptionsProbe
  @events = []
  def self.options
    @events << :receiver
    { page: 0, visible: false, optional: nil }
  end
  def self.defaults
    @events << :defaults
    { page: 7, visible: true, optional: 10, per_page: 30 }
  end
  def self.run
    result = options.reverse_merge!(defaults)
    raise "call evaluation order/count" unless @events == [:receiver, :defaults]
    raise "zero overwritten" unless result[:page] == 0
    raise "false overwritten" unless result[:visible] == false
    raise "nil overwritten" unless result[:optional].nil?
    raise "missing default" unless result[:per_page] == 30
    raise "merge insertion order" unless result.keys == [:page, :visible, :optional, :per_page]
    original = { page: 0 }
    defaults = { page: 7, per_page: 30 }
    alias_value = original
    returned = original.reverse_merge!(defaults)
    raise "receiver identity" unless returned.equal?(original) && alias_value[:per_page] == 30
    raise "defaults mutated" unless defaults == { page: 7, per_page: 30 }
    original.reverse_merge!(page: 9, per_page: 100)
    raise "keyword defaults" unless original[:page] == 0 && original[:per_page] == 30
    same = { page: 1 }
    same.reverse_merge!(same)
    raise "same hash alias" unless same == { page: 1 }
    with_default = Hash.new(7)
    with_default[:page] = 0
    default_source = Hash.new(9)
    default_source[:per_page] = 30
    with_default.reverse_merge!(default_source)
    raise "defaults not copied by replace" unless with_default[:missing] == 9
    frozen = { page: 0 }.freeze
    begin
      frozen.reverse_merge!(per_page: 30)
      raise "frozen receiver mutated"
    rescue FrozenError
    end
    puts "reverse options PASS"
  end
end
"#;
fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/reverse_options_probe.rb", SOURCE)
}
#[test]
fn source_default_merge_keeps_live_values_aliases_order_and_both_operand_effects() {
    let original = emit_and_run::ruby()
        .args([
            "-ractive_support/core_ext/hash/reverse_merge",
            "-e",
            &format!("{SOURCE}\nReverseOptionsProbe.run"),
        ])
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let run = app().run_ruby("ReverseOptionsProbe.run");
    run.assert_passes();
    assert_eq!(run.stdout.as_bytes(), original.stdout);
    let emitted =
        std::fs::read_to_string(run.emitted.join("app/models/reverse_options_probe.rb")).unwrap();
    assert!(
        emitted.contains("ActiveSupport.reverse_merge!"),
        "{emitted}"
    );
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn actual_default_options_operator_runs_natively() {
    let run = app().run_spinel_with_rbs("ReverseOptionsProbe.run");
    run.assert_passes();
    assert_eq!(run.stdout, "reverse options PASS\n");
}

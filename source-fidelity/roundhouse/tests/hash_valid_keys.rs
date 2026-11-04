#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;

const SOURCE: &str = r#"class OptionKeysProbe
  @events = []
  def self.keys
    @events << :keys
    [:page, :per_page]
  end
  def self.options
    @events << :receiver
    { page: 0, per_page: 20 }
  end
  def self.run
    hash = options
    original_keys = hash.keys
    allowed = keys
    result = hash.assert_valid_keys(allowed)
    raise "identity" unless result.equal?(hash)
    raise "hash mutation" unless hash.keys == original_keys
    raise "allowed mutation" unless allowed == [:page, :per_page]
    raise "value changed" unless result[:page] == 0 && result[:per_page] == 20
    raise "effects" unless @events == [:receiver, :keys]
    raise "empty hash" unless ({}).assert_valid_keys.empty?
    raise "scalar keys" unless { page: 0 }.assert_valid_keys(:page, :per_page)[:page] == 0
    raise "string keys" unless { "page" => 0 }.assert_valid_keys("page")["page"] == 0
    begin
      { bad: 1, worse: 2 }.assert_valid_keys([:page, :per_page])
      raise "invalid accepted"
    rescue ArgumentError => error
      raise error.message unless error.message == "Unknown key: :bad. Valid keys are: :page, :per_page"
    end
    begin
      { page: 0 }.assert_valid_keys(["page"])
      raise "coerced key"
    rescue ArgumentError => error
      raise error.message unless error.message == 'Unknown key: :page. Valid keys are: "page"'
    end
    puts "hash validation PASS"
  end
end
"#;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/option_keys_probe.rb", source)
}
#[test]
fn same_lowered_validation_preserves_values_identity_errors_and_effects() {
    let original = emit_and_run::ruby()
        .args([
            "-ractive_support/core_ext/hash/keys",
            "-e",
            &format!("{SOURCE}\nOptionKeysProbe.run"),
        ])
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let run = app(SOURCE).run_ruby("OptionKeysProbe.run");
    run.assert_passes();
    assert_eq!(run.stdout.as_bytes(), original.stdout);
    let emitted =
        std::fs::read_to_string(run.emitted.join("app/models/option_keys_probe.rb")).unwrap();
    assert!(
        emitted.contains("ActiveSupport.assert_valid_keys(hash, allowed)"),
        "{emitted}"
    );
}
#[test]
fn unknown_receiver_nested_keys_and_core_override_are_not_rewritten() {
    for source in [
        "class Other; def assert_valid_keys(value); value; end; end\nclass OptionKeysProbe; def self.run; Other.new.assert_valid_keys([:page]); end; end",
        "class OptionKeysProbe; def self.run; {page: 1}.assert_valid_keys([[:page]]); end; end",
        "class OptionKeysProbe; def self.run; {page: 1}.reverse_merge!(name: 'unproved new value type'); end; end",
        "class OptionKeysProbe; def self.run; {page: 1}.reverse_merge!({'other key type' => 2}); end; end",
        "class Hash; def assert_valid_keys(value); self; end; end\nclass OptionKeysProbe; def self.run; {page: 1}.assert_valid_keys([:page]); end; end",
    ] {
        let (out, errors) = app(source).emit(BuildTarget::Spinel);
        assert!(errors.is_empty(), "{errors:?}");
        let emitted = std::fs::read_to_string(out.join("app/models/option_keys_probe.rb")).unwrap();
        assert!(
            !emitted.contains("ActiveSupport.assert_valid_keys")
                && !emitted.contains("ActiveSupport.reverse_merge!"),
            "{emitted}"
        );
    }
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn validation_runs_natively_with_checked_hash_and_key_array_layouts() {
    let run = app(SOURCE).run_spinel_with_rbs("OptionKeysProbe.run");
    run.assert_passes();
    assert_eq!(run.stdout, "hash validation PASS\n");
}

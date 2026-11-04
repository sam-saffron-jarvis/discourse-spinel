//! Destructive recursive Hash key conversion, as used by YAML declaration
//! loaders. Container identity and collision order are part of the contract.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"class DeepKeysProbe
  def self.run
    child = { "flag" => false, "zero" => 0, "empty" => "", "nil" => nil }
    array = [child, { "more" => [ { "name" => "value" } ] }]
    hash = { "nested" => child, "array" => array, "collision" => 1, collision: 2, 7 => "integer" }
    result = hash.deep_symbolize_keys!
    raise "receiver identity" unless result.equal?(hash)
    raise "nested hash identity" unless hash[:nested].equal?(child)
    raise "nested array identity" unless hash[:array].equal?(array)
    raise "aliased child identity" unless array[0].equal?(child)
    raise "false" unless child[:flag] == false
    raise "zero" unless child[:zero] == 0
    raise "empty" unless child[:empty] == ""
    raise "nil" unless child[:nil].nil?
    raise "recursive array" unless array[1][:more][0][:name] == "value"
    raise "collision snapshot order" unless hash[:collision] == 1
    raise "integer key" unless hash[7] == "integer"
    raise "old key retained" if child.key?("flag")
    raise "empty" unless ({}).deep_symbolize_keys! == {}
    hash.deep_symbolize_keys!
    raise "idempotent content" unless child[:flag] == false
    puts "deep key mutation PASS"
  end
end
"#;

fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("app/models/deep_keys_probe.rb", source)
}

fn yaml_source() -> String {
    // YAML's open containers are the original loader's runtime shape. A
    // statically String-keyed nested literal has a separate compiler limit.
    SOURCE.replace("class DeepKeysProbe", "require \"yaml\"\nclass DeepKeysProbe")
        .replace(
            "    child = { \"flag\" => false, \"zero\" => 0, \"empty\" => \"\", \"nil\" => nil }\n    array = [child, { \"more\" => [ { \"name\" => \"value\" } ] }]\n    hash = { \"nested\" => child, \"array\" => array, \"collision\" => 1, collision: 2, 7 => \"integer\" }",
            "    hash = YAML.load(\"nested: &child\\n  flag: false\\n  zero: 0\\n  empty: ''\\n  nil: null\\narray:\\n  - *child\\n  - more:\\n      - name: value\\ncollision: 1\\n7: integer\\n\", aliases: true)\n    if hash.is_a?(Hash)\n    child = hash[\"nested\"]\n    array = hash[\"array\"]\n    hash[:collision] = 2"
        )
        .replace("    puts \"deep key mutation PASS\"", "    puts \"deep key mutation PASS\"\n    else\n      raise \"wrong YAML fixture type\"\n    end")
}

#[test]
fn destructive_deep_keys_run_on_emitted_ruby() {
    assert!(roundhouse::runtime_files::exists("runtime/ruby/hash_transform_keys.rb"), "shared runtime embedded");
    let run = app(SOURCE).run_ruby("DeepKeysProbe.run\n");
    run.assert_passes();
    assert_eq!(run.stdout, "deep key mutation PASS\n");
    let emitted = std::fs::read_to_string(run.emitted.join("app/models/deep_keys_probe.rb"))
        .expect("emitted probe");
    assert!(emitted.contains("ActiveSupport.deep_symbolize_keys!(hash)"), "{emitted}");
}

#[test]
fn wrapper_calls_invalidate_alias_key_evidence_too() {
    let source = SOURCE
        .replace("  def self.run", "  def self.convert(hash)\n    convert_inner(hash)\n  end\n  def self.convert_inner(hash)\n    hash.deep_symbolize_keys!\n  end\n  def self.run")
        .replace("result = hash.deep_symbolize_keys!", "result = convert(hash)")
        .replace("    hash.deep_symbolize_keys!\n    raise \"idempotent", "    convert(hash)\n    raise \"idempotent");
    let run = app(&source).run_ruby("DeepKeysProbe.run\n");
    run.assert_passes();
    assert_eq!(run.stdout, "deep key mutation PASS\n");
}

#[test]
fn yaml_deep_keys_run_on_emitted_ruby() {
    let run = app(&yaml_source()).run_ruby("DeepKeysProbe.run\n");
    run.assert_passes();
    assert_eq!(run.stdout, "deep key mutation PASS\n");
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn yaml_deep_keys_run_natively() {
    let run = app(&yaml_source()).run_spinel_with_rbs("DeepKeysProbe.run\n");
    run.assert_passes();
    assert_eq!(run.stdout, "deep key mutation PASS\n");
}

#[test]
#[ignore = "requires Spinel; pins the explicit unsupported nested literal layout"]
fn nested_string_keyed_literal_refuses_instead_of_losing_entries() {
    let run = app(SOURCE).run_spinel_with_rbs("DeepKeysProbe.run\n");
    assert!(run.errors.is_empty(), "{:?}", run.errors);
    assert!(!run.success);
    assert!(run.stderr.contains("hash was not widened for this store"), "{}", run.stderr);
}

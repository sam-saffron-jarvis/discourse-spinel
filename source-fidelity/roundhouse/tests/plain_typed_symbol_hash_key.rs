//! A Symbol's static type must not turn a plain Hash into an indifferent
//! store. Same contract as plain_string_hash_key, including typed keys.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const SOURCE: &str = r#"module TypedPlainKeys
  #: (Hash[String, untyped], Symbol) -> untyped
  def self.read(values, key)
    values[key]
  end
  #: (Hash[String, untyped], Symbol) -> untyped
  def self.fetch(values, key)
    values.fetch(key, :absent)
  end
  #: (Hash[String, untyped], Symbol) -> bool
  def self.has(values, key)
    values.key?(key)
  end
  #: (Hash[String, untyped], Symbol) -> untyped
  def self.remove(values, key)
    values.delete(key)
  end
  #: (Hash[String, untyped], Symbol, Integer) -> Integer
  def self.store(values, key, value)
    values[key] = value
  end
  #: (Hash[String, untyped], Symbol) -> untyped
  def self.nested(values, key)
    values.dig(key, :leaf)
  end
end
"#;

const PROBE: &str = r#"
values = { "x" => 1, x: 2 }
raise "typed Symbol read coerced" unless TypedPlainKeys.read(values, :x) == 2
raise "typed Symbol fetch coerced" unless TypedPlainKeys.fetch(values, :x) == 2
raise "typed Symbol presence" unless TypedPlainKeys.has(values, :x)
raise "typed Symbol delete coerced" unless TypedPlainKeys.remove(values, :x) == 2
raise "String entry was changed" unless values["x"] == 1
raise "missing Symbol became String hit" unless TypedPlainKeys.read(values, :x).nil?
raise "fetch miss" unless TypedPlainKeys.fetch(values, :x) == :absent
raise "presence miss" if TypedPlainKeys.has(values, :x)
TypedPlainKeys.store(values, :x, 3)
raise "Symbol store coerced" unless values[:x] == 3 && values["x"] == 1
nested = { "nest" => { leaf: 10 }, nest: { leaf: 20 } }
raise "dig coerced" unless TypedPlainKeys.nested(nested, :nest) == 20
puts "plain typed Hash keys PASS"
"#;

fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("lib/typed_plain_keys.rb", SOURCE)
}

#[test]
fn typed_symbol_keys_keep_plain_hash_semantics_on_emitted_ruby() {
    let run = app().run_ruby(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "plain typed Hash keys PASS\n");
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn typed_symbol_keys_keep_plain_hash_semantics_natively() {
    let run = app().run_spinel_with_rbs(PROBE);
    run.assert_passes();
    assert_eq!(run.stdout, "plain typed Hash keys PASS\n");
}

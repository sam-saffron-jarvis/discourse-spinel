//! Reduced from the core provider's mutually exclusive PG/JDBC source owners.
//! Source consumers keep both; emitted Ruby/Spinel inventories may select only
//! predicates on which both engines agree. This is not a provider/page proof.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

const ENTRY: &str = r#"$engine_dependency_events = []
module EngineDependency
end
if RUBY_ENGINE == 'jruby'
  require 'engine_dependency/jdbc'
else
  require 'engine_dependency/native'
end
$engine_dependency_events << :entry_complete
"#;
const NATIVE: &str = r#"$engine_dependency_events << :native_loaded
module EngineDependency
  class Connection
    def initialize(value, opts = nil)
      @answer = value + opts[:delta].to_i
    end
    attr_reader :answer
  end
end
"#;
const JDBC: &str = r#"$engine_dependency_events << :jdbc_loaded
module EngineDependency
  class Connection
    def initialize(value, delta: 0)
      @answer = value + delta + 1000
    end
    attr_reader :answer
  end
end
"#;
const CONSUMER: &str = r#"class EngineDependencyConsumer < EngineDependency::Connection
  def self.exercise
    raise 'source feature order/effects changed' unless $engine_dependency_events == [:native_loaded, :entry_complete]
    raise 'wrong inherited initializer or keyword ABI' unless new(17, delta: 5).answer == 22
    puts 'engine source dependency PASS'
  end
end
"#;

fn fixture(entry: &str, extra: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("roundhouse.yml", "extensions:\n  - config/roundhouse\n")
        .write("config/roundhouse/gems.yml", "source_gems:\n  - {gem: engine_dependency}\n")
        .write("config/application.rb", "Bundler.require(*Rails.groups)\n")
        .write("Gemfile", "source 'https://rubygems.org'\ngem 'engine_dependency'\n")
        .write("Gemfile.lock", "GEM\n  remote: https://rubygems.org/\n  specs:\n    engine_dependency (1.0)\n\nDEPENDENCIES\n  engine_dependency\n")
        .write(".bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n")
        .write("vendor/bundle/ruby/4.0.0/gems/engine_dependency-1.0/lib/engine_dependency.rb", entry)
        .write("vendor/bundle/ruby/4.0.0/gems/engine_dependency-1.0/lib/engine_dependency/native.rb", NATIVE)
        .write("vendor/bundle/ruby/4.0.0/gems/engine_dependency-1.0/lib/engine_dependency/jdbc.rb", JDBC)
        .write("lib/engine_dependency_consumer.rb", &format!("{CONSUMER}\n{extra}"))
}

#[test]
fn source_runtime_inventory_preserves_original_feature_effects_and_constructor() {
    check(false);
}

#[test]
#[ignore = "requires Spinel; no DB or external services"]
fn source_runtime_inventory_runs_natively() {
    check(true);
}

fn check(native: bool) {
    let (emitted, app, errors) = fixture(ENTRY, "").emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    assert!(app.source_gem_ruby_family_inventory);
    assert_eq!(app.library_classes.iter().filter(|class| class.name.0.as_str() == "EngineDependency::Connection").count(), 1);
    assert!(!app.sources.iter().any(|source| source.path.ends_with("engine_dependency/jdbc.rb")));
    let source = emitted.parent().unwrap().join("app");
    let original = emit_and_run::ruby().arg("-I").arg(source.join("vendor/bundle/ruby/4.0.0/gems/engine_dependency-1.0/lib"))
        .args(["-rengine_dependency", "-e"]).arg(format!("{CONSUMER}\nEngineDependencyConsumer.exercise\n")).output().unwrap();
    assert!(original.status.success(), "{}", String::from_utf8_lossy(&original.stderr));
    std::fs::write(emitted.join("engine_dependency.rb"), "require_relative 'app/models'\nEngineDependencyConsumer.exercise\n").unwrap();
    let lowered = emit_and_run::ruby().arg("engine_dependency.rb").current_dir(&*emitted).output().unwrap();
    assert!(lowered.status.success(), "{}", String::from_utf8_lossy(&lowered.stderr));
    assert_eq!(lowered.stdout, original.stdout);
    if native {
        let compiled = std::process::Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
            .args(["--load-model=graph", "--jobs=4", "--rbs", ".", "engine_dependency.rb", "-o", "engine_dependency"]).current_dir(&*emitted).output().unwrap();
        assert!(compiled.status.success(), "{}", String::from_utf8_lossy(&compiled.stderr));
        let result = std::process::Command::new(emitted.join("engine_dependency")).current_dir(&*emitted).output().unwrap();
        assert!(result.status.success(), "{}", String::from_utf8_lossy(&result.stderr));
        assert_eq!(result.stdout, original.stdout);
    }
    assert!(roundhouse::project::target_files(&app, &source, roundhouse::project::BuildTarget::Jruby).is_err(), "partitioned inventory accepted by an incompatible runtime");
    assert!(roundhouse::project::target_files(&app, &source, roundhouse::project::BuildTarget::Ruby).is_err(), "partitioned inventory accepted without the finite native graph");
    let unspecialized = roundhouse::ingest::ingest_app(&source).unwrap();
    assert!(!unspecialized.source_gem_ruby_family_inventory);
    assert_eq!(unspecialized.library_classes.iter().filter(|class| class.name.0.as_str() == "EngineDependency::Connection").count(), 2);
}


#[test]
fn runtime_source_profile_keeps_overrides_unknown_conditions_and_explicit_loads_refused() {
    for (entry, extra) in [
        (ENTRY.to_string(), "RUBY_ENGINE = 'jruby'"),
        (ENTRY.to_string(), "Object.const_set(:RUBY_ENGINE, 'jruby')"),
        (ENTRY.to_string(), "class String\n def ==(other); false; end\nend"),
        (ENTRY.to_string(), "require 'engine_dependency/jdbc'"),
        (ENTRY.replace("'jruby'", "'ruby'"), ""),
        (ENTRY.replace("RUBY_ENGINE == 'jruby'", "ENV['ADAPTER'] == 'jdbc'"), ""),
    ] {
        let (_, app, errors) = fixture(&entry, extra).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(!app.source_gem_ruby_family_inventory, "unproved world selected a source inventory: {extra}");
        assert_eq!(app.library_classes.iter().filter(|class| class.name.0.as_str() == "EngineDependency::Connection").count(), 2);
        assert!(!errors.is_empty(), "ambiguous constructor world became quiet");
    }
}

#[test]
fn runtime_source_profile_does_not_admit_computed_feature_mutations() {
    for extra in [
        "require ENV.fetch('OTHER_FEATURE')",
        "Object.const_get(:String).class_eval(ENV.fetch('MUTATION'))",
    ] {
        let (_, _, errors) = fixture(ENTRY, extra).emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(!errors.is_empty(), "computed feature or engine world became executable: {extra}");
    }
}


#[test]
fn selected_source_inventory_rechecks_late_ir_engine_mutations() {
    use roundhouse::expr::{Expr, ExprNode, Literal, LValue};
    use roundhouse::{ClassId, Symbol};
    let (emitted, original, errors) = fixture(ENTRY, "").emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let source = emitted.parent().unwrap().join("app");
    let mut changed = original.clone();
    changed.boot_program.push(Expr::new(roundhouse::span::Span::synthetic(), ExprNode::Assign {
        target: LValue::Const { path: vec![Symbol::from("RUBY_ENGINE")] },
        value: Expr::new(roundhouse::span::Span::synthetic(), ExprNode::Lit { value: Literal::Str { value: "jruby".into() } }),
    }));
    assert!(roundhouse::project::target_files(&changed, &source, roundhouse::project::BuildTarget::Spinel).is_err(), "late engine write bypassed feature proof");
    let mut program_changed = original.clone();
    program_changed.file_programs[0].items.push(roundhouse::app::ProgramItem::Statement(changed.boot_program.last().unwrap().clone()));
    assert!(roundhouse::project::target_files(&program_changed, &source, roundhouse::project::BuildTarget::Spinel).is_err(), "late feature-program engine write bypassed feature proof");
    let mut changed = original;
    let mut core = changed.library_classes.iter().find(|class| class.name.0.as_str() == "EngineDependencyConsumer").unwrap().clone();
    core.name = ClassId(Symbol::from("String"));
    core.parent = None;
    changed.library_classes.push(core);
    assert!(roundhouse::project::target_files(&changed, &source, roundhouse::project::BuildTarget::Spinel).is_err(), "late core declaration bypassed feature proof");
}

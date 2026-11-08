//! Closed feature/binding lowering, not plugin activation or arbitrary eval.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

use roundhouse::project::BuildTarget;
use std::path::Path;
use std::process::Command;

const GEM: &str = "vendor/bundle/ruby/4.0.0/gems/finitekit-1.0/lib";
const ENTRY: &str = r#"$feature_events = []
$feature_loads = 0
require_relative "finitekit/cycle"
module Finitekit
  autoload :Value, "finitekit/value"
  autoload :Unused, "finitekit/unused"
  OUTER = 41
  @registered = !defined?(Value).nil?
  @loads_at_body = $feature_loads
  def self.registered
    @registered
  end
  def self.loads_at_body
    @loads_at_body
  end
end
"#;
const VALUE: &str = r#"$feature_loads += 1
$feature_events << "value#{$feature_loads}"
module Finitekit
  class Value
    INNER = 1
    def self.answer
      OUTER + INNER
    end
  end
end
raise ArgumentError, "load failed" if $feature_loads == 1
"#;
const CYCLE: &str = "$feature_events << 'cycle'\nrequire_relative '../finitekit'\n";
const UNUSED: &str = "$feature_events << 'unused'\nmodule Finitekit\n  class Unused\n    def self.answer\n      9\n    end\n  end\nend\n";

fn app(entry: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("roundhouse.yml", "extensions:\n  - config/roundhouse\n")
        .write("config/roundhouse/gems.yml", "source_gems:\n  - {gem: \"finitekit\"}\n")
        .write("config/application.rb", "Bundler.require(*Rails.groups)\n")
        .write("Gemfile", "source \"https://rubygems.org\"\ngem \"finitekit\"\n")
        .write("Gemfile.lock", "GEM\n  remote: https://rubygems.org/\n  specs:\n    finitekit (1.0)\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  finitekit\n\nBUNDLED WITH\n   2.6.9\n")
        .write(".bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n")
        .write(&format!("{GEM}/finitekit.rb"), entry)
        .write(&format!("{GEM}/finitekit/value.rb"), VALUE)
        .write(&format!("{GEM}/finitekit/cycle.rb"), CYCLE)
        .write(&format!("{GEM}/finitekit/unused.rb"), UNUSED)
}

fn probe(value: &Path, entry: &Path) -> String {
    format!(
        r#"
raise "registration moved after body" unless Finitekit.registered
raise "eager autoload body" unless Finitekit.loads_at_body == 0 && $feature_loads == 0
raise "circular/repeated require ran twice" unless $feature_events == ["cycle"]
begin
  Finitekit::Value.answer
rescue ArgumentError => error
  $feature_events << error.message
end
raise "first load did not fail" unless $feature_loads == 1
raise "failed load lost its pending binding" unless defined?(Finitekit::Value) == "constant"
raise "retry lost value" unless Finitekit::Value.answer == 42
raise "failed load was cached" unless $feature_loads == 2
raise "constant read reloaded successful feature" unless Finitekit::Value.answer == 42 && $feature_loads == 2
raise "require/autoload feature identity diverged" unless require({value:?}) == false
raise "entry feature alias diverged" unless require({entry:?}) == false
raise "unread autoload ran" if $feature_events.include?("unused")
puts $feature_events.join("|")
"#,
        value = value.to_string_lossy(),
        entry = entry.to_string_lossy()
    )
}

fn ruby_sources(root: &Path) -> std::collections::BTreeMap<std::path::PathBuf, Vec<u8>> {
    fn collect(root: &Path, files: &mut std::collections::BTreeMap<std::path::PathBuf, Vec<u8>>) {
        for entry in std::fs::read_dir(root).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                collect(&path, files);
            } else if path.extension().is_some_and(|extension| extension == "rb") {
                files.insert(path.clone(), std::fs::read(path).unwrap());
            }
        }
    }
    let mut files = std::collections::BTreeMap::new();
    collect(root, &mut files);
    files
}

#[test]
fn finite_programs_share_lazy_cache_cycle_failure_and_retry_semantics() {
    check_finite_program(ENTRY, "", "");
}

#[test]
fn ordered_plain_mattr_events_compose_with_lazy_features_and_retry() {
    let entry = ENTRY.replace(
        "  OUTER = 41",
        "  mattr_accessor :quiet\n  NIL_AT_MACRO = quiet.nil?\n  @@quiet = false\n  OUTER = 41",
    );
    check_finite_program(
        &entry,
        "require 'active_support/core_ext/module/attribute_accessors'\n",
        "raise 'nil/bool macro body order' unless Finitekit::NIL_AT_MACRO && Finitekit.quiet == false\n",
    );
}

fn check_finite_program(entry: &str, original_prelude: &str, extra_probe: &str) {
    let (emitted, errors) = app(entry).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let original = emitted.join("original-lib");
    for (name, source) in [
        ("finitekit.rb", entry),
        ("finitekit/value.rb", VALUE),
        ("finitekit/cycle.rb", CYCLE),
        ("finitekit/unused.rb", UNUSED),
    ] {
        let file = original.join(name);
        std::fs::create_dir_all(file.parent().unwrap()).unwrap();
        std::fs::write(file, source).unwrap();
    }
    let original_script = format!(
        "{original_prelude}$LOAD_PATH.unshift({:?})\nrequire 'finitekit'\n{}{extra_probe}",
        original.to_string_lossy(),
        probe(&original.join("finitekit/value.rb"), &original.join("finitekit.rb"))
    );
    std::fs::write(emitted.join("original.rb"), original_script).unwrap();
    let original_before = ruby_sources(&original);
    let control = emit_and_run::ruby()
        .arg("original.rb")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert_eq!(
        ruby_sources(&original),
        original_before,
        "original source mutated during control"
    );
    std::fs::write(emitted.join("original.stdout"), &control.stdout).unwrap();
    std::fs::write(emitted.join("original.stderr"), &control.stderr).unwrap();
    assert!(control.status.success(), "{}", String::from_utf8_lossy(&control.stderr));
    assert_eq!(
        String::from_utf8_lossy(&control.stdout).trim(),
        "cycle|value1|load failed|value2"
    );

    let feature = emitted.join("app/models/roundhouse_files/.roundhouse/source_gems/finitekit-1.0/lib/finitekit");
    let script = format!(
        "require_relative 'app/models'\n{}{extra_probe}",
        probe(&feature.join("value.rb"), &feature.with_extension("rb"))
    );
    std::fs::write(emitted.join("probe.rb"), script).unwrap();
    let lowered_before = ruby_sources(&emitted);
    let ruby = emit_and_run::ruby()
        .arg("probe.rb")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    std::fs::write(emitted.join("lowered.stdout"), &ruby.stdout).unwrap();
    std::fs::write(emitted.join("lowered.stderr"), &ruby.stderr).unwrap();
    assert!(ruby.status.success(), "{}", String::from_utf8_lossy(&ruby.stderr));
    assert_eq!(ruby.stdout, control.stdout, "same lowered Ruby versus original");
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compiled = Command::new(compiler)
        .args(["--load-model=graph", "--jobs=4", "probe.rb", "-o", "probe"])
        .current_dir(&*emitted)
        .output()
        .unwrap();
    std::fs::write(emitted.join("compile.stderr"), &compiled.stderr).unwrap();
    assert!(
        compiled.status.success(),
        "{}\n{}",
        emitted.display(),
        String::from_utf8_lossy(&compiled.stderr)
    );
    assert_eq!(&std::fs::read(emitted.join("probe")).unwrap()[..4], b"\x7fELF");
    let native = Command::new(emitted.join("probe"))
        .current_dir(&*emitted)
        .output()
        .unwrap();
    std::fs::write(emitted.join("native.stdout"), &native.stdout).unwrap();
    std::fs::write(emitted.join("native.stderr"), &native.stderr).unwrap();
    if std::env::var_os("ROUNDHOUSE_KEEP_EMITTED").is_some() {
        let label = if entry == ENTRY {
            "FINITE_FILE_PROGRAM_EVIDENCE"
        } else {
            "ORDERED_MATTR_FILE_PROGRAM_EVIDENCE"
        };
        eprintln!("{label}={}", emitted.display());
    }
    assert!(native.status.success(), "{}", String::from_utf8_lossy(&native.stderr));
    assert_eq!(native.stdout, ruby.stdout, "native must run the same lowered files");
    assert_eq!(
        ruby_sources(&emitted),
        lowered_before,
        "lowered files mutated between CRuby/native execution"
    );
    let aggregator = std::fs::read_to_string(emitted.join("app/models.rb")).unwrap();
    assert!(!aggregator.contains("RoundhouseAutoload.entering"));
    assert!(!aggregator.contains("require_relative \"models/finitekit/value\""));
}

#[test]
fn reflective_queries_still_refuse_instead_of_enabling_the_cruby_helper() {
    let (_, errors) = app(&ENTRY.replace("!defined?(Value).nil?", "!autoload?(:Value).nil?")).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("finite native file-program profile") && e.contains("autoload?")),
        "{errors:#?}"
    );
}

#[test]
fn an_overridden_owner_protocol_is_not_replaced_with_a_builtin_registration() {
    let source = ENTRY.replace(
        "  @registered =",
        "  def self.autoload(name, path)\n    nil\n  end\n  @registered =",
    );
    let (_, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("finite native file-program profile") && e.contains("overridden")),
        "{errors:#?}"
    );
}

#[test]
fn a_missing_resource_is_not_made_available_by_eager_declarations() {
    let (_, errors) = app(&ENTRY.replace("finitekit/unused", "finitekit/not_present")).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("finite native file-program profile") && e.contains("missing/unknown resource")),
        "{errors:#?}"
    );
}

#[test]
fn a_plain_require_before_its_owner_does_not_get_a_hoisted_namespace() {
    let source = ENTRY.replacen(
        "module Finitekit",
        "require_relative 'finitekit/value'\nmodule Finitekit",
        1,
    );
    let (_, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("finite native file-program profile") && e.contains("unknown/missing owner")),
        "{errors:#?}"
    );
}

#[test]
fn a_changed_owner_binding_is_not_treated_as_the_original_namespace() {
    let source = format!("{ENTRY}\nFinitekit = Object.new\n");
    let (_, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("finite native file-program profile") && e.contains("reassigned")),
        "{errors:#?}"
    );
}

#[test]
fn dynamic_resource_and_late_registration_worlds_remain_refused() {
    for source in [
        ENTRY.replace(
            "autoload :Value, \"finitekit/value\"",
            "autoload :Value, ENV.fetch('UNPROVED_FEATURE')",
        ),
        ENTRY.replace("  autoload :Value", "  BEFORE = 1\n  autoload :Value"),
        format!("$LOAD_PATH.unshift('/unproved/search/root')\n{ENTRY}"),
    ] {
        let (_, errors) = app(&source).emit(BuildTarget::Spinel);
        assert!(
            errors.iter().any(|e| e.contains("finite native file-program profile")),
            "{errors:#?}"
        );
    }
}

#[test]
fn resource_mutation_is_not_frozen_into_a_native_feature() {
    let source = format!("File.write('finitekit/value.rb', 'changed resource')\n{ENTRY}");
    let (_, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|e| e.contains("finite native file-program profile") && e.contains("resource mutation")),
        "{errors:#?}"
    );
}

#[test]
fn failed_autoload_class_state_and_escaping_values_are_not_static_metadata() {
    for value in [
        VALUE.replace(
            "    INNER = 1",
            "    @attempts ||= 0\n    @attempts += 1\n    INNER = 1",
        ),
        VALUE.replace("      OUTER + INNER", "      self"),
        VALUE.replace(
            "raise ArgumentError",
            "$escaped_class = Finitekit::Value\nraise ArgumentError",
        ),
    ] {
        let (_, errors) = app(ENTRY)
            .write(&format!("{GEM}/finitekit/value.rb"), &value)
            .emit(BuildTarget::Spinel);
        assert!(
            errors
                .iter()
                .any(|error| error.contains("finite native file-program profile")
                    && (error.contains("fresh-allocation") || error.contains("escape"))),
            "{errors:#?}"
        );
    }
}

#[test]
fn unpositioned_module_attributes_are_not_admitted_by_the_file_program_plan() {
    let source = ENTRY.replace("  OUTER = 41", "  mattr_accessor :unproved, default: []\n  OUTER = 41");
    let (_, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|error| error.contains("finite native file-program profile")
                && error.contains("unpositioned mattr/cattr")),
        "{errors:#?}"
    );
}

#[test]
fn an_unknown_declaration_callback_is_not_silently_discarded() {
    let source = ENTRY.replace(
        "  OUTER = 41",
        "  opaque_initializer :unproved do\n    $feature_events << 'initializer'\n  end\n  OUTER = 41",
    );
    let (_, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(
        errors
            .iter()
            .any(|error| error.contains("finite native file-program profile")
                && error.contains("unmodelled declaration-body effect")),
        "{errors:#?}"
    );
}

// Exact byte-for-byte original discourse-seed-fu 2.3.12 version.rb member.
// The reduced entry below is NOT its original main/Railtie/application.
const SEEDFU_VERSION: &str = "module SeedFu\n  # The current version of Seed Fu\n  VERSION = '2.3.12'\nend\n";
const CONSTANT_ENTRY: &str = r#"module SeedFu
  autoload :VERSION, 'finitekit/version'
  mattr_accessor :quiet
  @@quiet = false
  mattr_accessor :fixture_paths
  @@fixture_paths = ['db/fixtures']
end
"#;

#[test]
fn exact_original_version_reopen_keeps_its_own_lazy_constant_feature() {
    check_literal_constant_feature(SEEDFU_VERSION, true);
}

#[test]
fn a_frozen_source_literal_feature_keeps_its_actual_allocation_policy() {
    check_literal_constant_feature(&format!("# frozen_string_literal: true\n{SEEDFU_VERSION}"), false);
}

fn check_literal_constant_feature(version_source: &str, mutable: bool) {
    let (emitted, errors) = app(CONSTANT_ENTRY)
        .write(&format!("{GEM}/finitekit/version.rb"), version_source)
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let original = emitted.join("constant-original-lib");
    std::fs::create_dir_all(original.join("finitekit")).unwrap();
    std::fs::write(original.join("finitekit.rb"), CONSTANT_ENTRY).unwrap();
    std::fs::write(original.join("finitekit/version.rb"), version_source).unwrap();
    let feature = emitted.join("app/models/roundhouse_files/.roundhouse/source_gems/finitekit-1.0/lib/finitekit");
    let assertions = |version: &Path| format!(r#"
raise 'source nil/false order' unless SeedFu.quiet == false
raise 'source paths' unless SeedFu.fixture_paths == ['db/fixtures']
paths = SeedFu.fixture_paths
paths << 'live producer'
raise 'live storage identity' unless SeedFu.fixture_paths.equal?(paths)
if ARGV.first == 'require-first'
  raise 'literal feature ran eagerly' unless require({version:?}) == true
end
raise 'literal value' unless SeedFu::VERSION == '2.3.12'
raise 'shared cached String' unless SeedFu::VERSION.equal?(SeedFu::VERSION)
raise 'canonical feature cache' unless require({version:?}) == false
if {mutable}
  SeedFu::VERSION << '-live'
  raise 'literal mutable storage' unless SeedFu::VERSION == '2.3.12-live'
else
  raise 'source frozen literal thawed' unless SeedFu::VERSION.frozen?
end
puts 'original VERSION feature and main storage PASS'
"#, version = version.to_string_lossy(), mutable = mutable);
    std::fs::write(emitted.join("constant-original.rb"), format!("require 'active_support/core_ext/module/attribute_accessors'\n$LOAD_PATH.unshift({:?})\nrequire 'finitekit'\n{}", original.to_string_lossy(), assertions(&original.join("finitekit/version.rb")))).unwrap();
    std::fs::write(emitted.join("constant-probe.rb"), format!("require_relative 'app/models'\n{}", assertions(&feature.join("version.rb")))).unwrap();
    // The version assignment must not leak into the main owner's body.
    let main = std::fs::read_to_string(feature.with_extension("rb")).unwrap();
    assert!(!main.contains("VERSION =") && !main.contains("2.3.12"), "{main}");
    let version = std::fs::read_to_string(feature.join("version.rb")).unwrap();
    assert!(version.contains("SeedFu::VERSION ="), "{version}");
    let before = ruby_sources(&emitted);
    let compiled = Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
        .args(["--load-model=graph", "--jobs=4", "constant-probe.rb", "-o", "constant-probe"])
        .current_dir(&*emitted).output().unwrap();
    std::fs::write(emitted.join("constant-compile.stderr"), &compiled.stderr).unwrap();
    assert!(compiled.status.success(), "{}\n{}", emitted.display(), String::from_utf8_lossy(&compiled.stderr));
    assert_eq!(&std::fs::read(emitted.join("constant-probe")).unwrap()[..4], b"\x7fELF");
    for mode in ["autoload-first", "require-first"] {
        let original = emit_and_run::ruby().args(["constant-original.rb", mode]).current_dir(&*emitted).output().unwrap();
        let lowered = emit_and_run::ruby().args(["constant-probe.rb", mode]).current_dir(&*emitted).output().unwrap();
        let native = Command::new(emitted.join("constant-probe")).arg(mode).current_dir(&*emitted).output().unwrap();
        for (label, output) in [("original", &original), ("lowered", &lowered), ("native", &native)] {
            std::fs::write(emitted.join(format!("constant-{mode}-{label}.stdout")), &output.stdout).unwrap();
            std::fs::write(emitted.join(format!("constant-{mode}-{label}.stderr")), &output.stderr).unwrap();
            assert!(output.status.success(), "{mode} {label}: {}", String::from_utf8_lossy(&output.stderr));
        }
        assert_eq!(original.stdout, lowered.stdout);
        assert_eq!(lowered.stdout, native.stdout);
    }
    assert_eq!(before, ruby_sources(&emitted));
    if std::env::var_os("ROUNDHOUSE_KEEP_EMITTED").is_some() {
        eprintln!("ORIGINAL_CONSTANT_FEATURE_EVIDENCE={}", emitted.display());
    }
}


#[test]
fn literal_feature_does_not_admit_changed_or_stateful_namespace_reopens() {
    for source in [
        SEEDFU_VERSION.replace("module SeedFu", "class SeedFu"),
        SEEDFU_VERSION.replace("'2.3.12'", "['2.3.12']"),
        SEEDFU_VERSION.replace("'2.3.12'", "('2.3.12' + '-computed')"),
        SEEDFU_VERSION.replace("  VERSION", "  include UnprovedAncestor\n  VERSION"),
        format!("{SEEDFU_VERSION}\n$extra_file_effect = true\n"),
        SEEDFU_VERSION.replace("  VERSION", "  def self.mattr_accessor(*names); nil; end\n  VERSION"),
        SEEDFU_VERSION.replace("  VERSION", "  def self.const_added(name); nil; end\n  VERSION"),
    ] {
        let tree = [
            ("config/routes.rb".to_string(), "Rails.application.routes.draw do\nend\n".to_string()),
            ("roundhouse.yml".to_string(), "extensions:\n  - config/roundhouse\n".to_string()),
            ("config/roundhouse/gems.yml".to_string(), "source_gems:\n  - {gem: \"finitekit\"}\n".to_string()),
            ("config/application.rb".to_string(), "Bundler.require(*Rails.groups)\n".to_string()),
            ("Gemfile".to_string(), "source \"https://rubygems.org\"\ngem \"finitekit\"\n".to_string()),
            ("Gemfile.lock".to_string(), "GEM\n  remote: https://rubygems.org/\n  specs:\n    finitekit (1.0)\n\nPLATFORMS\n  ruby\n\nDEPENDENCIES\n  finitekit\n\nBUNDLED WITH\n   2.6.9\n".to_string()),
            (".bundle/config".to_string(), "---\nBUNDLE_PATH: \"vendor/bundle\"\n".to_string()),
            (format!("{GEM}/finitekit.rb"), CONSTANT_ENTRY.to_string()),
            (format!("{GEM}/finitekit/version.rb"), source.clone()),
        ].into_iter().map(|(path, source)| (std::path::PathBuf::from(path), source.into_bytes())).collect();
        // A strict ingest refusal is the expected outcome, not an emitter test
        // that assumes ingestion succeeded and accidentally tests a pruned app.
        let result = roundhouse::ingest::ingest_app_from_tree(tree);
        let error = result.err().expect("stateful/unproved reopen must refuse").to_string();
        assert!(error.contains("ordered plain mattr") || error.contains("class-variable initialization"), "{error}\n{source}");
    }
}

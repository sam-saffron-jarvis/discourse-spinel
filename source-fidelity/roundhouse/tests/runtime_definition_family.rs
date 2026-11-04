//! Runtime singleton families preserve event timing, captured values and the
//! eventual class receiver; no literal reader is installed ahead of the event.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
const SOURCE: &str = r#"class RuntimeValueFamily
  @events = []
  @callback_presence = []
  #: () -> Array[Symbol]
  def self.events
    @events
  end
  #: () -> Array[bool]
  def self.callback_presence
    @callback_presence
  end
  #: (Hash[Symbol, Integer] values) -> Hash[Symbol, Integer]
  def self.seed(values)
    @values = values
  end
  #: (bool alternative) -> Symbol
  def self.install(alternative)
    key = alternative ? :alternative : :answer
    delta = 0
    installed = define_singleton_method(key) { @frame_names = [__method__, __callee__]; @values[key] + delta }
    delta = 5
    installed
  end
  #: () -> Array[Symbol]
  def self.frame_names
    @frame_names
  end
  #: (bool alternative) -> Symbol
  def self.replace(alternative)
    key = alternative ? :alternative : :answer
    define_singleton_method(key) { @values[key] + 100 }
  end
  #: () -> Integer
  def self.reset_queries
    @queries = 0
    @flags = 0
  end
  #: (Symbol value) -> Symbol
  def self.query_name(value)
    @queries = @queries + 1
    value
  end
  #: (bool value) -> bool
  def self.query_private(value)
    @flags = @flags + 1
    value
  end
  #: () -> Array[Integer]
  def self.query_effects
    [@queries, @flags]
  end
  def self.exercise(alternative)
    reset_queries
    raise "absent query" if respond_to?(query_name(:missing), query_private(false))
    raise "absent query repeated operands" unless query_effects == [1, 1]
    raise "native table fallback" unless respond_to?(query_name(:seed), query_private(false))
    raise "native fallback repeated operands" unless query_effects == [2, 2]
    raise "private native table fallback" unless respond_to?(query_name(:singleton_method_added), query_private(true))
    raise "private fallback repeated operands" unless query_effects == [3, 3]
    key = alternative ? :alternative : :answer
    seed({ answer: 17, alternative: 19 })
    raise "visible before installation" if respond_to?(key)
    before_events = events.dup
    install(alternative)
    raise "definition callback order/count" unless events == before_events + [key]
    raise "callback did not see installed method" unless callback_presence.last
    raise "missing installed method" unless respond_to?(key)
    expected = alternative ? 19 : 17
    child_expected = alternative ? 29 : 23
    raise "root capture" unless public_send(key) == expected + 5
    raise "root method frame" unless frame_names == [key, key]
    begin
      ChildRuntimeValueFamily.public_send(key)
      raise "uninitialized child storage did not fail"
    rescue NoMethodError
    end
    ChildRuntimeValueFamily.seed({ answer: 23, alternative: 29 })
    raise "child receiver" unless ChildRuntimeValueFamily.public_send(key) == child_expected + 5
    raise "child method frame" unless ChildRuntimeValueFamily.frame_names == [key, key]
    before = method(key)
    singleton_class.alias_method(:raw, key)
    raise "alias callback missing" unless events == before_events + [key, :raw]
    raw = method(:raw)
    raise "alias Method equality" unless before == raw
    raise "alias name" unless raw.name == :raw && raw.original_name == key
    raise "bound receiver" unless raw.receiver.equal?(self)
    raise "bound arity" unless raw.arity == 0
    replace(alternative)
    raise "replacement callback missing" unless events == before_events + [key, :raw, key]
    raise "old Method did not snapshot" unless before.call == expected + 5
    raise "alias did not snapshot" unless raw.call == expected + 5
    raise "alias method frame" unless frame_names == [key, :raw]
    raise "new Method identity collapsed" if method(key) == before
    raise "replacement" unless public_send(key) == expected + 100
    private_class_method(key)
    raise "private visibility" if respond_to?(key)
    raise "private visibility include_private" unless respond_to?(key, true)
    begin
      public_send(key)
      raise "public_send bypassed visibility"
    rescue NoMethodError
    end
    raise "private bind/call" unless method(key).call == expected + 100
    public_class_method(key)
    raise "public restore" unless respond_to?(key)
    raise "visibility generated callback" unless events == before_events + [key, :raw, key]
    puts "runtime family event PASS"
  end
  #: (Symbol name) -> Array[bool]
  def self.singleton_method_added(name)
    events << name
    callback_presence << respond_to?(name, true)
  end
  private_class_method :singleton_method_added
end
class ChildRuntimeValueFamily < RuntimeValueFamily
end
"#;
fn app() -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/runtime_value_family.rb", SOURCE)
}
#[test]
fn runtime_installation_protocol_matches_original_and_lowered_ruby() {
    for alternative in [false, true] {
        let probe = format!("RuntimeValueFamily.exercise({alternative})");
        let original = emit_and_run::ruby()
            .args(["--enable-frozen-string-literal", "-e"])
            .arg(format!("{SOURCE}\n{probe}"))
            .output()
            .expect("run original runtime definition event");
        assert!(
            original.status.success(),
            "{}",
            String::from_utf8_lossy(&original.stderr)
        );
        let (emitted, typed, errors) =
            app().emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(errors.is_empty(), "{errors:#?}");
        assert_eq!(
            typed.runtime_definition_families.len(),
            1,
            "runtime family was not represented in shared IR"
        );
        let mut requires = String::new();
        // Body-only app-model dependencies are loaded by the project models
        // aggregator. This pure consumer loads the same concrete family files
        // explicitly, without booting a DB adapter or changing their bodies.
        for relative in [
            "roundhouse_runtime_family0/roundhouse_runtime_family0_state",
            "roundhouse_runtime_family0",
            "roundhouse_runtime_family0/roundhouse_runtime_family0_entry",
            "roundhouse_runtime_family0/roundhouse_runtime_family0_slot",
            "roundhouse_runtime_family0/roundhouse_runtime_family0_bound_method",
        ] {
            requires.push_str(&format!("require_relative 'app/models/{relative}'\n"));
        }
        let lowered = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
            .arg(format!("{requires}require_relative 'app/models/runtime_value_family'\nrequire_relative 'app/models/child_runtime_value_family'\n{probe}"))
            .current_dir(&*emitted).output().expect("run lowered runtime definition event");
        assert!(
            lowered.status.success(),
            "{}",
            String::from_utf8_lossy(&lowered.stderr)
        );
        assert_eq!(original.stdout, lowered.stdout);
    }
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn runtime_family_runs_natively_with_emitted_signatures() {
    let (emitted, errors) = app().emit(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    // This first language-core owning proof needs no Rails runtime. Compile
    // exactly the same lowered class/helper files the CRuby consumer loads.
    let mut consumer = String::new();
    for relative in [
        "roundhouse_runtime_family0/roundhouse_runtime_family0_state",
        "roundhouse_runtime_family0",
        "roundhouse_runtime_family0/roundhouse_runtime_family0_entry",
        "roundhouse_runtime_family0/roundhouse_runtime_family0_slot",
        "roundhouse_runtime_family0/roundhouse_runtime_family0_bound_method",
        "runtime_value_family",
        "child_runtime_value_family",
    ] {
        consumer.push_str(&format!("require_relative 'app/models/{relative}'\n"));
    }
    consumer.push_str("RuntimeValueFamily.exercise(ARGV.length > 0)\n");
    std::fs::write(emitted.join("family_contract.rb"), consumer).unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compiled = std::process::Command::new(compiler)
        .args(["--rbs", ".", "family_contract.rb", "-o", "family_contract"])
        .current_dir(&*emitted)
        .output()
        .expect("compile minimal family consumer");
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    for arguments in [Vec::<&str>::new(), vec!["alternative"]] {
        let native = std::process::Command::new(emitted.join("family_contract"))
            .args(arguments)
            .current_dir(&*emitted)
            .output()
            .expect("run native family event");
        assert!(
            native.status.success(),
            "{}",
            String::from_utf8_lossy(&native.stderr)
        );
        assert_eq!(native.stdout, b"runtime family event PASS\n");
    }
}

#[test]
#[ignore = "requires Spinel; full framework integration, no external services"]
fn runtime_family_full_framework_boot_remains_executable() {
    let run = app().run_spinel_with_rbs("RuntimeValueFamily.exercise(ARGV.length > 0)");
    run.assert_passes();
    assert_eq!(run.stdout, "runtime family event PASS\n");
}

#[test]
fn generated_runtime_method_bodies_have_closed_types() {
    let (_emitted, typed, errors) = app().emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    fn check(expr: &roundhouse::expr::Expr, path: &str, unresolved: &mut Vec<String>) {
        if expr.ty.as_ref().is_none_or(|ty| ty.mentions_unknown()) {
            unresolved.push(format!("{path}: {:?} has {:?}", expr.node, expr.ty));
        }
        expr.node
            .for_each_child(&mut |child| check(child, path, unresolved));
    }
    let mut unresolved = Vec::new();
    for class in typed
        .library_classes
        .iter()
        .filter(|class| class.name.0.as_str().starts_with("RoundhouseRuntimeFamily"))
    {
        for method in &class.methods {
            check(
                &method.body,
                &format!("{}#{}", class.name.0, method.name),
                &mut unresolved,
            );
        }
    }
    fn lifted(expr: &roundhouse::expr::Expr, unresolved: &mut Vec<String>) {
        if let roundhouse::expr::ExprNode::Send {
            recv: Some(recv),
            method,
            args,
            ..
        } = &*expr.node
            && method.as_str() == "install"
            && matches!(&*recv.node, roundhouse::expr::ExprNode::Const { path } if path.first().is_some_and(|name| name.as_str().starts_with("RoundhouseRuntimeFamily")))
        {
            check(&args[2], "lifted explicit-receiver body", unresolved);
        }
        expr.node
            .for_each_child(&mut |child| lifted(child, unresolved));
    }
    for class in &typed.library_classes {
        for method in &class.methods {
            lifted(&method.body, &mut unresolved);
        }
    }
    assert!(unresolved.is_empty(), "{}", unresolved.join("\n"));
}

#[test]
fn unsupported_observers_mutations_frames_and_escapes_keep_original_refusal() {
    let cases = [
        ("argument template", SOURCE.replace("{ @frame_names = [__method__, __callee__]; @values[key] + delta }", "{ |argument| @values[key] }")),
        ("nonlocal frame", SOURCE.replace("{ @frame_names = [__method__, __callee__]; @values[key] + delta }", "{ return @values[key] }")),
        ("compound ivar write", SOURCE.replace("{ @frame_names = [__method__, __callee__]; @values[key] + delta }", "{ @counter ||= 0; @counter += 1 }")),
        ("nullable runtime name", SOURCE.replace("key = alternative ? :alternative : :answer", "key = ARGV.first")),
        ("conditional invalid name type", SOURCE.replacen("define_singleton_method(key)", "key = 17 if alternative\n    define_singleton_method(key)", 1)),
        ("defined? observer", SOURCE.replace("before_events = events.dup", "defined?(answer)\n    before_events = events.dup")),
        ("owner equality override", SOURCE.replace("class ChildRuntimeValueFamily < RuntimeValueFamily\nend", "class ChildRuntimeValueFamily < RuntimeValueFamily\n def self.==(other); true; end\nend")),
        ("exception metadata", SOURCE.replace("rescue NoMethodError\n", "rescue NoMethodError => error\n      error.name\n")),
        ("method-table observer", SOURCE.replace("before_events = events.dup", "singleton_methods\n    before_events = events.dup")),
        ("method-table mutation", SOURCE.replace("    replace(alternative)", "    singleton_class.remove_method(key)\n    replace(alternative)")),
        ("bound Method owner", SOURCE.replace("raw = method(:raw)", "raw = method(:raw)\n    raw.owner")),
        ("bound Method escape", SOURCE.replace("puts \"runtime family event PASS\"", "before")),
        ("bound receiver virtual call", SOURCE.replace("raw = method(:raw)", "raw = method(:raw)\n    raw.receiver.public_send(key)")),
        ("class escape", SOURCE.replace("seed({ answer: 17", "klass = self\n    seed({ answer: 17")),
        ("descendant incompatible storage", SOURCE.replace("class ChildRuntimeValueFamily < RuntimeValueFamily\nend", "class ChildRuntimeValueFamily < RuntimeValueFamily\n def self.other_seed; @values = { answer: true }; end\nend")),
        ("dynamic storage mutation", SOURCE.replace("before_events = events.dup", "instance_variable_set(key, 1)\n    before_events = events.dup")),
        ("visibility result escape", SOURCE.replace("    private_class_method(key)", "    owner = private_class_method(key)")),
        ("descendant protocol override", SOURCE.replace("class ChildRuntimeValueFamily < RuntimeValueFamily\nend", "class ChildRuntimeValueFamily < RuntimeValueFamily\n def self.respond_to?(name); false; end\nend")),
        ("core conversion override", format!("{SOURCE}\nclass Symbol\n def to_sym; :wrong; end\nend\n")),
    ];
    for (label, source) in cases {
        let (_emitted, typed, errors) = emit_and_run::empty_app()
            .write(
                "config/routes.rb",
                "Rails.application.routes.draw do\nend\n",
            )
            .write("lib/runtime_value_family.rb", &source)
            .emit_with_app(roundhouse::project::BuildTarget::Spinel);
        assert!(
            typed.runtime_definition_families.is_empty(),
            "{label}: unsupported family was admitted"
        );
        assert!(
            errors
                .iter()
                .any(|error| error.message.contains("runtime-defined method")),
            "{label}: original unsupported boundary vanished: {errors:#?}"
        );
    }
}

fn all_model_requires(root: &std::path::Path) -> String {
    fn collect(root: &std::path::Path, paths: &mut Vec<std::path::PathBuf>) {
        for entry in std::fs::read_dir(root).unwrap() {
            let path = entry.unwrap().path();
            if path.is_dir() {
                collect(&path, paths);
            } else if path.extension().is_some_and(|ext| ext == "rb") {
                paths.push(path);
            }
        }
    }
    let mut paths = Vec::new();
    collect(&root.join("app/models"), &mut paths);
    paths.sort();
    paths
        .iter()
        .map(|path| {
            format!(
                "require_relative '{}'\n",
                path.strip_prefix(root).unwrap().display()
            )
        })
        .collect()
}
#[test]
fn two_families_avoid_existing_helper_names_and_preserve_storage() {
    let second = SOURCE.replace("RuntimeValueFamily", "SecondRuntimeValueFamily");
    let original = emit_and_run::ruby().args(["--enable-frozen-string-literal", "-e"])
        .arg(format!("{SOURCE}\n{second}\nRuntimeValueFamily.exercise(false)\nSecondRuntimeValueFamily.exercise(true)"))
        .output().unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let (emitted, typed, errors) = app()
        .write("lib/second_runtime_value_family.rb", &second)
        .write(
            "lib/helper_collision.rb",
            "class RoundhouseRuntimeFamily0\nend\n",
        )
        .emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    assert_eq!(typed.runtime_definition_families.len(), 2);
    let registries: std::collections::BTreeSet<_> = typed
        .runtime_definition_families
        .iter()
        .map(|family| family.registry.0.as_str())
        .collect();
    assert_eq!(registries.len(), 2);
    assert!(!registries.contains("RoundhouseRuntimeFamily0"));
    let lowered = emit_and_run::ruby()
        .args(["--enable-frozen-string-literal", "-e"])
        .arg(format!(
            "{}RuntimeValueFamily.exercise(false)\nSecondRuntimeValueFamily.exercise(true)",
            all_model_requires(&emitted)
        ))
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        lowered.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(lowered.stdout, original.stdout);
}
#[test]
#[ignore = "requires Spinel; no external services"]
fn empty_full_framework_control_without_runtime_family() {
    // Diagnose the full-runtime empty-app boundary separately; do not remove
    // Flash/AR code from a full-boot proof or report it as family acceptance.
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .run_spinel_with_rbs("puts 'empty full framework PASS'")
        .assert_passes();
}

#[test]
#[ignore = "requires Spinel; no external services"]
fn two_runtime_families_run_natively_with_helper_name_collision() {
    let second = SOURCE.replace("RuntimeValueFamily", "SecondRuntimeValueFamily");
    let (emitted, typed, errors) = app()
        .write("lib/second_runtime_value_family.rb", &second)
        .write(
            "lib/helper_collision.rb",
            "class RoundhouseRuntimeFamily0\nend\n",
        )
        .emit_with_app(roundhouse::project::BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    assert_eq!(typed.runtime_definition_families.len(), 2);
    std::fs::write(emitted.join("two_families.rb"), format!("{}RuntimeValueFamily.exercise(ARGV.length > 0)\nSecondRuntimeValueFamily.exercise(ARGV.length == 0)\n", all_model_requires(&emitted))).unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compiled = std::process::Command::new(compiler)
        .args(["--rbs", ".", "two_families.rb", "-o", "two_families"])
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(
        compiled.status.success(),
        "{}",
        String::from_utf8_lossy(&compiled.stderr)
    );
    for arguments in [vec![], vec!["alternative"]] {
        let native = std::process::Command::new(emitted.join("two_families"))
            .args(arguments)
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(
            native.status.success(),
            "{}",
            String::from_utf8_lossy(&native.stderr)
        );
        assert_eq!(
            native.stdout,
            b"runtime family event PASS\nruntime family event PASS\n"
        );
    }
}

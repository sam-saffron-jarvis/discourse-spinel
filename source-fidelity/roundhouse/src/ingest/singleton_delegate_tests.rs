//! Shared-IR singleton delegate controls. Native forwarding remains refused;
//! these compare the actual ActiveSupport macro with the same lowered Ruby.
use super::*;

const SOURCE: &str = r#"
class SingletonDelegateTarget
  def read(*values, **options, &block)
    result = [values, options]
    block ? block.call(result) : result
  end
  def name
    'target'
  end
  def value=(value)
    @value = value
    :ignored_setter_return
  end
  def boom
    raise NoMethodError.new('inside target', :inside)
  end
end
class SingletonDelegateRelay
  def read
    :original_instance_method
  end
  def self.singleton_method_added(name)
    $definition_events << name if [:read, :name, :value=, :boom, :to_s, :maybe_name].include?(name)
  end
  class << self
    attr_writer :target
    def target
      $target_reads += 1
      raise NoMethodError.new('inside getter', :read) if $getter_raises
      @target
    end
    private
    delegate :read, :name, :value=, :boom, to: :target
    public
    delegate :to_s, to: :target, allow_nil: true
    delegate :name, to: :target, prefix: :maybe, allow_nil: true
  end
end
"#;
const DRIVER: &str = r#"
require 'json'
raise 'class declaration overwrote instance method' unless SingletonDelegateRelay.new.read == :original_instance_method
SingletonDelegateRelay.target = SingletonDelegateTarget.new
results = []
results << SingletonDelegateRelay.read(1, { k: 2 }, k: 3)
results << SingletonDelegateRelay.read(4, k: 5) { |args| [args, 'block'] }
def nonlocal_delegate_return
  SingletonDelegateRelay.read(8) { |value| return ['nonlocal', value] }
  raise 'nonlocal block return lost'
end
results << nonlocal_delegate_return
results << SingletonDelegateRelay.method(:value=).call(9)
results << [:read, :value=].map { |name| [name, SingletonDelegateRelay.method(name).arity, SingletonDelegateRelay.method(name).parameters] }
begin
  SingletonDelegateRelay.boom
rescue NoMethodError => e
  results << [e.class.name, e.message, e.name]
end
SingletonDelegateRelay.target = nil
results << SingletonDelegateRelay.maybe_name
results << SingletonDelegateRelay.to_s
begin
  SingletonDelegateRelay.name
rescue ActiveSupport::DelegationError => e
  results << [e.class.name, e.message]
end
$getter_raises = true
begin
  SingletonDelegateRelay.read
rescue ActiveSupport::DelegationError => e
  results << [e.class.name, e.message]
end
puts JSON.generate([results, $target_reads, $definition_events])
"#;

#[test]
fn singleton_delegate_receiver_formals_errors_effects_and_callbacks_match_original() {
    let mut app = crate::App::default();
    app.library_classes = crate::ingest::ingest_library_classes(SOURCE.as_bytes(), "singleton-delegates.rb").unwrap();
    lower_delegates(&mut app);
    let relay = app
        .library_classes
        .iter()
        .find(|class| class.name.0.as_str() == "SingletonDelegateRelay")
        .unwrap();
    assert!(
        relay.unknown_calls.iter().all(|call| !is_delegate_declaration(call)),
        "literal class macros not consumed"
    );
    let read = relay
        .methods
        .iter()
        .find(|method| method.name.as_str() == "read" && method.receiver == MethodReceiver::Class)
        .unwrap();
    assert!(
        read.params.iter().any(|param| param.forwarding),
        "source variadic ABI was narrowed to zero arguments"
    );
    assert!(read.body.declaration_step().is_some());
    let writer = relay
        .methods
        .iter()
        .find(|method| method.name.as_str() == "value=" && method.receiver == MethodReceiver::Class)
        .unwrap();
    assert_eq!(writer.params.len(), 1);
    assert!(!writer.params[0].forwarding);
    let files = crate::emit::ruby::emit_library(&app);
    let lowered = files
        .iter()
        .filter(|file| file.path.extension().is_some_and(|ext| ext == "rb"))
        .map(|file| file.content.as_str())
        .collect::<Vec<_>>()
        .join("\n");
    let prelude = "$definition_events = []; $target_reads = 0; $getter_raises = false\n";
    let ruby = |source: &str| {
        let output = std::process::Command::new("ruby")
            .args([
                "--enable-frozen-string-literal",
                "-ractive_support/core_ext/module/delegation",
                "-e",
            ])
            .arg(format!("{prelude}{source}\n{DRIVER}"))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}\nSOURCE:\n{source}",
            String::from_utf8_lossy(&output.stderr)
        );
        output.stdout
    };
    let original_output = ruby(SOURCE);
    let lowered_output = ruby(&lowered);
    if let Some(path) = std::env::var_os("ROUNDHOUSE_SINGLETON_DELEGATE_ARCHIVE") {
        let path = std::path::PathBuf::from(path);
        std::fs::create_dir(&path).expect("archive subject directory must be fresh");
        let require = "require 'active_support/core_ext/module/delegation'\n";
        std::fs::write(path.join("original.rb"), format!("{require}{prelude}{SOURCE}\n{DRIVER}")).unwrap();
        std::fs::write(path.join("lowered.rb"), format!("{require}{prelude}{lowered}\n{DRIVER}")).unwrap();
        std::fs::write(path.join("original.stdout"), &original_output).unwrap();
        std::fs::write(path.join("lowered.stdout"), &lowered_output).unwrap();
        std::fs::write(path.join("lowered-ir.json"), serde_json::to_vec_pretty(&app).unwrap()).unwrap();
    }
    assert_eq!(
        original_output,
        lowered_output,
        "singleton macro changed receiver, ABI, nil/error behavior, lookup count or callback order"
    );
}

#[test]
fn singleton_and_instance_declarations_with_same_name_are_not_deduplicated_together() {
    let source = "class SideSpecificDelegates\n  delegate :name, to: :instance_target\n  class << self\n    delegate :name, to: :class_target\n  end\nend\n";
    let mut class = crate::ingest::ingest_library_class(source.as_bytes(), "side-delegates.rb")
        .unwrap()
        .unwrap();
    let methods = expand_delegates_in_class(&mut class);
    assert_eq!(
        methods.iter().filter(|method| method.name.as_str() == "name").count(),
        2
    );
    assert!(
        methods.iter().any(
            |method| method.receiver == MethodReceiver::Class && method.params.iter().any(|param| param.forwarding)
        )
    );
    assert!(
        methods
            .iter()
            .any(|method| method.receiver == MethodReceiver::Instance && method.params.is_empty())
    );
}

#[test]
fn singleton_redefinitions_retain_source_event_order_and_later_explicit_definition() {
    let source = r#"
class OrderedSingletonDelegates
  def self.singleton_method_added(name)
    $ordered_events << name if [:first, :second].include?(name)
  end
  class << self
    def target; 'target'; end
    def first; :before; end
    delegate :first, :second, to: :target
    delegate :first, to: :target
    def first; :after; end
  end
end
"#;
    let mut app = crate::App::default();
    app.library_classes =
        crate::ingest::ingest_library_classes(source.as_bytes(), "ordered-singleton-delegates.rb").unwrap();
    lower_delegates(&mut app);
    let class = &app.library_classes[0];
    assert_eq!(
        class
            .methods
            .iter()
            .filter(|method| method.name.as_str() == "first")
            .count(),
        4
    );
    let files = crate::emit::ruby::emit_library(&app);
    let lowered = &files
        .iter()
        .find(|file| file.path.extension().is_some_and(|ext| ext == "rb"))
        .unwrap()
        .content;
    let run = |source: &str| {
        let output = std::process::Command::new("ruby")
            .args(["-ractive_support/core_ext/module/delegation", "-e"])
            .arg(format!(
                "$ordered_events = []\n{source}\np [$ordered_events, OrderedSingletonDelegates.first]\n"
            ))
            .output()
            .unwrap();
        assert!(
            output.status.success(),
            "{}\n{source}",
            String::from_utf8_lossy(&output.stderr)
        );
        output.stdout
    };
    assert_eq!(run(source), run(lowered));
}

#[test]
fn native_singleton_delegation_keeps_the_unverified_forwarding_carrier_refusal() {
    let mut app = crate::App::default();
    app.library_classes = crate::ingest::ingest_library_classes(SOURCE.as_bytes(), "singleton-delegates.rb").unwrap();
    lower_delegates(&mut app);
    let (_, diagnostics) = crate::emit::diagnostics::scope(|| {
        crate::project::target_files(&app, crate::fixtures::real_blog(), crate::project::BuildTarget::Spinel)
    });
    assert!(
        diagnostics
            .iter()
            .any(|diagnostic| diagnostic.severity == crate::diagnostic::Severity::Error
                && matches!(&diagnostic.kind, crate::diagnostic::DiagnosticKind::Unsupported { construct, .. }
            if construct.as_str() == "full argument forwarding")),
        "source receiver fix silently admitted an unverified native ABI: {diagnostics:#?}"
    );
}

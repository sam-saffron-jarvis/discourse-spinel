//! Source-only namespace wrappers must not merge a helper into its later
//! parent feature. These controls use no database or application observations.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;

const GEM: &str = "vendor/bundle/ruby/4.0.0/gems/namespace_feature-1.0/lib";
const ENTRY: &str = r#"$namespace_events = []
if RUBY_ENGINE == 'jruby'
  require 'namespace_feature/alternate'
else
  require 'namespace_feature/main'
end
$namespace_events << :entry
"#;
const MAIN: &str = r#"require_relative 'left'
require_relative 'right'
require_relative 'left'
$namespace_events << :after_helpers
module NamespaceFeature
  class Owner
    DEFAULT = 41
    def self.answer
      Child.read + 1
    end
    def initialize(value)
      @value = value
    end
    attr_reader :value
  end
end
$namespace_events << :main
"#;
const LEFT: &str = r#"$namespace_events << :left
module NamespaceFeature
  class Owner
    class Child
      def self.read
        DEFAULT
      end
      def initialize(value)
        @value = value
      end
      attr_reader :value
    end
  end
end
raise 'main methods exposed in helper' if NamespaceFeature::Owner.respond_to?(:answer)
begin
  NamespaceFeature::Owner::Child.read
  raise 'future constant exposed in helper'
rescue NameError
  $namespace_events << :constant_absent
end
"#;
const RIGHT: &str = r#"$namespace_events << :right
module NamespaceFeature
  module Marker
  end
  class Owner
    class Other
      include Marker
      def self.read
        Child.read
      end
    end
  end
end
raise 'main methods exposed in second helper' if NamespaceFeature::Owner.respond_to?(:answer)
"#;
const CHECK: &str = r#"raise 'feature effects/order changed' unless $namespace_events == [:left, :constant_absent, :right, :after_helpers, :main, :entry]
raise 'late lexical constant lookup changed' unless NamespaceFeature::Owner.answer == 42
raise 'sibling lexical lookup changed' unless NamespaceFeature::Owner::Other.read == 41
raise 'child include dropped' unless NamespaceFeature::Owner::Other.new.is_a?(NamespaceFeature::Marker)
raise 'nested constructor ownership changed' unless NamespaceFeature::Owner::Child.new(17).value == 17
puts 'source namespace features PASS'
"#;

fn consumer() -> String {
    format!("class NamespaceFeatureConsumer\n  def self.exercise\n{CHECK}\n  end\nend\n")
}

fn fixture(main: &str, left: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .write("roundhouse.yml", "extensions:\n  - config/roundhouse\n")
        .write("config/roundhouse/gems.yml", "source_gems:\n  - {gem: namespace_feature}\n")
        .write("config/application.rb", "Bundler.require(*Rails.groups)\n")
        .write("Gemfile", "source 'https://rubygems.org'\ngem 'namespace_feature'\n")
        .write("Gemfile.lock", "GEM\n  remote: https://rubygems.org/\n  specs:\n    namespace_feature (1.0)\n\nDEPENDENCIES\n  namespace_feature\n")
        .write(".bundle/config", "---\nBUNDLE_PATH: \"vendor/bundle\"\n")
        .write(&format!("{GEM}/namespace_feature.rb"), ENTRY)
        .write(&format!("{GEM}/namespace_feature/alternate.rb"), "$namespace_events << :jruby\n")
        .write(&format!("{GEM}/namespace_feature/main.rb"), main)
        .write(&format!("{GEM}/namespace_feature/left.rb"), left)
        .write(&format!("{GEM}/namespace_feature/right.rb"), RIGHT)
        .write("lib/namespace_feature_consumer.rb", &consumer())
}

#[test]
fn namespace_wrappers_preserve_original_features_under_same_lowered_ruby() {
    check(false);
}

#[test]
#[ignore = "requires Spinel; no DB or external services"]
fn namespace_wrappers_preserve_original_features_natively() {
    check(true);
}

fn check(native: bool) {
    let (emitted, _, errors) = fixture(MAIN, LEFT).emit_with_app(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let source = emitted.parent().unwrap().join("app");
    let original = emit_and_run::ruby()
        .arg("-I")
        .arg(source.join(GEM))
        .args(["-rnamespace_feature", "-e"])
        .arg(format!("{}\nNamespaceFeatureConsumer.exercise\n", consumer()))
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    std::fs::write(
        emitted.join("namespace_feature.rb"),
        "require_relative 'app/models'\nNamespaceFeatureConsumer.exercise\n",
    )
    .unwrap();
    let lowered = emit_and_run::ruby()
        .arg("namespace_feature.rb")
        .current_dir(&*emitted)
        .output()
        .unwrap();
    assert!(lowered.status.success(), "{}", String::from_utf8_lossy(&lowered.stderr));
    assert_eq!(lowered.stdout, original.stdout);
    if native {
        let compiled = std::process::Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
            .args([
                "--load-model=graph",
                "--jobs=4",
                "--rbs",
                ".",
                "namespace_feature.rb",
                "-o",
                "namespace_feature",
            ])
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(
            compiled.status.success(),
            "{}",
            String::from_utf8_lossy(&compiled.stderr)
        );
        let output = std::process::Command::new(emitted.join("namespace_feature"))
            .current_dir(&*emitted)
            .output()
            .unwrap();
        assert!(output.status.success(), "{}", String::from_utf8_lossy(&output.stderr));
        assert_eq!(output.stdout, original.stdout);
    }
}

#[test]
fn real_reopens_superclasses_kind_changes_and_callbacks_remain_refused() {
    for (main, left) in [
        (
            MAIN.to_string(),
            LEFT.replace("    class Child", "    EXTRA = 7\n    class Child"),
        ),
        (
            MAIN.replace("  class Owner", "  class Owner < Object"),
            LEFT.to_string(),
        ),
        (MAIN.replace("  class Owner", "  module Owner"), LEFT.to_string()),
        (
            MAIN.to_string(),
            LEFT.replace(
                "    class Child",
                "    def self.const_added(name); end\n    class Child",
            ),
        ),
        (MAIN.to_string(), format!("{LEFT}\nNamespaceFeature::Owner = Object\n")),
        (MAIN.to_string(), format!("{LEFT}\nNamespaceFeature = Object\n")),
        (MAIN.to_string(), format!("{LEFT}\nNamespaceFeature::Owner.new\n")),
        (
            MAIN.to_string(),
            format!("{LEFT}\n$escaped_namespace = NamespaceFeature::Owner\n"),
        ),
        (
            MAIN.to_string(),
            LEFT.replace("    class Child", "    class Child < NamespaceFeature::Owner"),
        ),
        (
            MAIN.replace(
                "    DEFAULT = 41",
                "    def self.build; new(1); end\n    @early = build\n    DEFAULT = 41",
            ),
            LEFT.to_string(),
        ),
    ] {
        let (_, _, errors) = fixture(&main, &left).emit_with_app(BuildTarget::Spinel);
        assert!(!errors.is_empty(), "unproved namespace world admitted: {main}\n{left}");
    }
}

#[test]
fn namespace_source_and_empty_record_proofs_are_rechecked_after_ir_mutation() {
    let (emitted, app, errors) = fixture(MAIN, LEFT).emit_with_app(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    let source = emitted.parent().unwrap().join("app");
    let mut changed = app.clone();
    let wrapper = changed
        .library_classes
        .iter_mut()
        .find(|class| class.name.0.as_str() == "NamespaceFeature::Owner" && class.methods.is_empty())
        .unwrap();
    wrapper.constants.push((
        roundhouse::Symbol::from("EXTRA"),
        roundhouse::expr::Expr::new(
            roundhouse::span::Span::synthetic(),
            roundhouse::expr::ExprNode::Lit {
                value: roundhouse::expr::Literal::Int { value: 7 },
            },
        ),
    ));
    assert!(
        roundhouse::project::target_files(&changed, &source, BuildTarget::Spinel).is_err(),
        "late wrapper member dropped"
    );
    let mut changed = app.clone();
    let file = changed
        .sources
        .iter_mut()
        .find(|file| file.path.ends_with("namespace_feature/left.rb"))
        .unwrap();
    file.text = file.text.replace("    class Child", "    EXTRA = 7\n    class Child");
    assert!(
        roundhouse::project::target_files(&changed, &source, BuildTarget::Spinel).is_err(),
        "changed source proof trusted"
    );
    let mut changed = app.clone();
    let record = changed
        .library_classes
        .iter_mut()
        .find(|class| class.name.0.as_str() == "NamespaceFeature::Owner::Child")
        .unwrap();
    let method = record
        .methods
        .iter_mut()
        .find(|method| method.name.as_str() == "read")
        .unwrap();
    method.body = roundhouse::expr::Expr::new(
        method.body.span,
        roundhouse::expr::ExprNode::Const {
            path: vec![
                roundhouse::Symbol::from("NamespaceFeature"),
                roundhouse::Symbol::from("Owner"),
            ],
        },
    );
    assert!(
        roundhouse::project::target_files(&changed, &source, BuildTarget::Spinel).is_err(),
        "late namespace value escape admitted"
    );
}

#[test]
fn app_member_patch_is_source_labelled_not_merged_into_the_gem_owner() {
    let (_, _, errors) = fixture(MAIN, LEFT)
        .write(
            "lib/namespace_owner_patch.rb",
            "module NamespaceFeature\n  class Owner\n    def self.patched; 7; end\n  end\nend\n",
        )
        .emit_with_app(BuildTarget::Spinel);
    let diagnostic = format!("{errors:#?}");
    assert!(
        diagnostic.contains("NamespaceFeature::Owner has no single feature identity"),
        "{diagnostic}"
    );
    assert!(diagnostic.contains("lib/namespace_owner_patch.rb"), "{diagnostic}");
    assert!(diagnostic.contains("no ordered file-program identity"), "{diagnostic}");
}

#[test]
fn two_real_member_features_keep_their_records_and_refuse_a_single_resource_binding() {
    let main = MAIN.replace(
        "    DEFAULT = 41",
        "    def self.singleton_method_added(name)\n      $namespace_events << [:added, name] unless name == :singleton_method_added\n    end\n    DEFAULT = 41",
    ) + "\nraise 'future patch API exposed in main' if NamespaceFeature::Owner.respond_to?(:patched)\nrequire_relative 'patch'\n";
    let patch = r#"module NamespaceFeature
  class Owner
    def self.patched
      answer + 1
    end
  end
end
$namespace_events << :patch
"#;
    let (emitted, app, errors) = fixture(&main, LEFT)
        .write(&format!("{GEM}/namespace_feature/patch.rb"), patch)
        .emit_with_app(BuildTarget::Spinel);
    let source = emitted.parent().unwrap().join("app");
    let original = emit_and_run::ruby()
        .arg("-I")
        .arg(source.join(GEM))
        .args(["-rnamespace_feature", "-e"])
        .arg(r#"expected = [:left, :constant_absent, :right, :after_helpers, [:added, :answer], :main, [:added, :patched], :patch, :entry]
raise 'source member callbacks/order changed' unless $namespace_events == expected
raise 'main member lost' unless NamespaceFeature::Owner.answer == 42
raise 'patch member lost' unless NamespaceFeature::Owner.patched == 43
puts 'original two-member-feature control PASS; native admission remains refused'
"#)
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let owners: Vec<_> = app
        .library_classes
        .iter()
        .filter(|class| class.name.0.as_str() == "NamespaceFeature::Owner" && !class.methods.is_empty())
        .collect();
    assert_eq!(owners.len(), 2, "real source member records merged or omitted");
    assert!(
        owners
            .iter()
            .any(|class| class.methods.iter().any(|method| method.name.as_str() == "answer"))
    );
    assert!(
        owners
            .iter()
            .any(|class| class.methods.iter().any(|method| method.name.as_str() == "patched"))
    );
    let diagnostic = format!("{errors:#?}");
    assert!(diagnostic.contains("has no single feature identity"), "{diagnostic}");
}

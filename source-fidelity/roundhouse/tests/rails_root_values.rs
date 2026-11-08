//! Raw Rails root values, not paths normalized by the observer.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;

const PROBE: &str = r#"module RootValueProbe
  def self.root
    Rails.root
  end
  def self.path
    Rails.root.to_s
  end
  def self.public_path
    Rails.public_path.to_s
  end
end
"#;

const CHECK: &str = r#"require "pathname"
require "tmpdir"
expected = Pathname.new(Dir.pwd)
raise "relative/fake root" unless RootValueProbe.path == expected.to_s
raise "public root differs" unless RootValueProbe.public_path == expected.join("public").to_s
first = RootValueProbe.root
raise "root identity" unless first.equal?(RootValueProbe.root)
text = first.to_s
text << "/caller-mutation"
path = first.to_path
path << "/caller-path-mutation"
raise "returned strings alias path storage" unless RootValueProbe.path == expected.to_s
Dir.mktmpdir("root-value-") do |other|
  Dir.chdir(other) do
    raise "chdir moved root" unless RootValueProbe.path == expected.to_s
    raise "chdir moved public path" unless RootValueProbe.public_path == expected.join("public").to_s
  end
end
puts "root values PASS"
"#;

#[test]
fn raw_root_values_are_absolute_boot_stable_and_do_not_expose_mutable_storage() {
    let run = emit_and_run::empty_app()
        .write("lib/root_value_probe.rb", PROBE)
        .run_ruby(CHECK);
    run.assert_passes();
    assert_eq!(run.stdout, "root values PASS\n");
}

#[test]
#[ignore = "requires Spinel; no services"]
fn native_root_captures_runtime_boot_directory_before_any_root_read() {
    let (out, errors) = emit_and_run::empty_app()
        .write("lib/root_value_probe.rb", PROBE)
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    // Read root only AFTER moving away from the boot cwd. No literal fixture
    // path or compiler cwd may be captured instead of the executing program.
    let entry = r#"require_relative "runtime/base64"
require_relative "runtime/active_support_ext"
require_relative "runtime/rails"
require_relative "app/models"
expected = File.expand_path(".")
Dir.chdir("/tmp")
raise "first read followed chdir" unless RootValueProbe.path == expected
raise "public root moved" unless RootValueProbe.public_path == expected + "/public"
raise "root identity" unless RootValueProbe.root.equal?(RootValueProbe.root)
text = RootValueProbe.root.to_s
text << "/caller-mutation"
path = RootValueProbe.root.to_path
path << "/caller-path-mutation"
raise "returned strings alias path storage" unless RootValueProbe.path == expected
puts "native root values PASS"
"#;
    std::fs::write(out.join("probe.rb"), entry).unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let compile = std::process::Command::new(compiler)
        .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        compile.status.success(),
        "{}",
        String::from_utf8_lossy(&compile.stderr)
    );
    let other = out.join("different boot root");
    std::fs::create_dir(&other).unwrap();
    for cwd in [&*out, other.as_path()] {
        let native = std::process::Command::new(out.join("probe"))
            .current_dir(cwd)
            .output()
            .unwrap();
        assert!(
            native.status.success(),
            "{}",
            String::from_utf8_lossy(&native.stderr)
        );
        assert_eq!(native.stdout, b"native root values PASS\n");
    }
}

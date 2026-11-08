#[path = "support/emit_and_run.rs"]
mod emit_and_run;
use roundhouse::project::BuildTarget;
const SOURCE: &str = r#"class JsonFileProbe
  @reads = 0
  def self.path
    @reads += 1
    "payload.json"
  end
  def self.run
    text = JSON.generate(JSON.load_file(path))
    raise "path evaluated twice" unless @reads == 1
    puts text
    begin
      JSON.load_file("invalid.json")
      raise "invalid JSON accepted"
    rescue JSON::ParserError
      puts "parse error"
    end
    begin
      JSON.load_file("missing.json")
      raise "missing file accepted"
    rescue Errno::ENOENT
      puts "read error"
    end
  end
end
"#;
fn app(source: &str) -> emit_and_run::Overlay {
    emit_and_run::empty_app()
        .write(
            "config/routes.rb",
            "Rails.application.routes.draw do\nend\n",
        )
        .write("lib/json_file_probe.rb", source)
        .write("payload.json", "[\"café\",false,null,0]\n")
        .write("invalid.json", "{not json")
}
const OBSERVE: &str = "require 'json'\nJsonFileProbe.run\n";
#[test]
fn load_file_keeps_live_utf8_read_errors_and_once_only_path_evaluation() {
    let (out, errors) = app(SOURCE).emit(BuildTarget::Spinel);
    std::fs::write(out.join("payload.json"), "[\"café\",false,null,0]\n").unwrap();
    std::fs::write(out.join("invalid.json"), "{not json").unwrap();
    assert!(errors.is_empty(), "{errors:#?}");
    let text = std::fs::read_to_string(out.join("app/models/json_file_probe.rb")).unwrap();
    assert!(
        text.contains("JSON.parse(::File.read(path, encoding: \"UTF-8\"))"),
        "{text}"
    );
    // load_file explicitly reads UTF-8 even when the ambient read encoding differs.
    let original = emit_and_run::ruby().args(["-e", &format!("require 'json'\nEncoding.default_external = Encoding::ASCII_8BIT\n{SOURCE}\n{OBSERVE}")]).current_dir(&*out).output().unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    let lowered = emit_and_run::ruby().args(["-e", &format!("require 'json'\nEncoding.default_external = Encoding::ASCII_8BIT\nrequire_relative 'app/models'\n{OBSERVE}")]).current_dir(&*out).output().unwrap();
    assert!(
        lowered.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(original.stdout, lowered.stdout);
}
#[test]
#[ignore = "requires Spinel; no services"]
fn load_file_composition_executes_natively() {
    let (out, errors) = app(SOURCE).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(out.join("payload.json"), "[\"café\",false,null,0]\n").unwrap();
    std::fs::write(out.join("invalid.json"), "{not json").unwrap();
    std::fs::write(
        out.join("probe.rb"),
        format!("require 'json'\nrequire_relative 'app/models'\n{OBSERVE}"),
    )
    .unwrap();
    let compiler = std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into());
    let build = std::process::Command::new(compiler)
        .args(["--jobs=4", "--rbs", ".", "probe.rb", "-o", "probe"])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        build.status.success(),
        "{}",
        String::from_utf8_lossy(&build.stderr)
    );
    let native = std::process::Command::new(out.join("probe"))
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        native.status.success(),
        "{}",
        String::from_utf8_lossy(&native.stderr)
    );
    let control = emit_and_run::ruby()
        .args(["-e", &format!("require 'json'\n{SOURCE}\n{OBSERVE}")])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        control.status.success(),
        "{}",
        String::from_utf8_lossy(&control.stderr)
    );
    assert_eq!(native.stdout, control.stdout);
}
#[test]
fn file_read_is_rooted_outside_the_callers_constant_scope() {
    let source = SOURCE.replace(
        "class JsonFileProbe\n",
        "class JsonFileProbe\n  File = String\n",
    );
    let (out, errors) = app(&source).emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:#?}");
    std::fs::write(out.join("payload.json"), "[\"café\",false,null,0]\n").unwrap();
    std::fs::write(out.join("invalid.json"), "{not json").unwrap();
    let original = emit_and_run::ruby()
        .args(["-e", &format!("require 'json'\n{source}\n{OBSERVE}")])
        .current_dir(&*out)
        .output()
        .unwrap();
    let lowered = emit_and_run::ruby()
        .args([
            "-e",
            &format!("require 'json'\nrequire_relative 'app/models'\n{OBSERVE}"),
        ])
        .current_dir(&*out)
        .output()
        .unwrap();
    assert!(
        original.status.success(),
        "{}",
        String::from_utf8_lossy(&original.stderr)
    );
    assert!(
        lowered.status.success(),
        "{}",
        String::from_utf8_lossy(&lowered.stderr)
    );
    assert_eq!(original.stdout, lowered.stdout);
}
#[test]
fn options_blocks_unknown_paths_and_core_overrides_keep_the_original_send() {
    for source in [
        "class JsonFileProbe; def self.load; JSON.load_file('payload.json', symbolize_names: true); end; end",
        "class JsonFileProbe; def self.load(path); JSON.load_file(path); end; end",
        "class JsonFileProbe; def self.load; JSON.load_file('payload.json') { 1 }; end; end",
        "module JSON; def self.load_file(path); path; end; end\nclass JsonFileProbe; def self.load; JSON.load_file('payload.json'); end; end",
        "module Scoped; module JSON; def self.load_file(path); path; end; end; end\nclass JsonFileProbe; def self.load; JSON.load_file('payload.json'); end; end",
        "class File; def self.read(path); '[]'; end; end\nclass JsonFileProbe; def self.load; JSON.load_file('payload.json'); end; end",
    ] {
        let (out, _) = app(source).emit(BuildTarget::Spinel);
        let text = std::fs::read_to_string(out.join("app/models/json_file_probe.rb")).unwrap();
        assert!(text.contains("JSON.load_file("), "{text}");
        assert!(!text.contains("JSON.parse(::File.read("), "{text}");
    }
}

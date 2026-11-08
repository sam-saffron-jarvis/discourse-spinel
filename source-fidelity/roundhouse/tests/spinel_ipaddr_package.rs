//! The emitted runtime must not overwrite bundled IPAddr with the octet port.
#[path = "support/emit_and_run.rs"]
mod emit_and_run;

use roundhouse::project::BuildTarget;
use std::process::Command;

fn tree() -> emit_and_run::Emitted {
    let (tree, errors) = emit_and_run::empty_app()
        .write("config/routes.rb", "Rails.application.routes.draw do\nend\n")
        .emit(BuildTarget::Spinel);
    assert!(errors.is_empty(), "{errors:?}");
    let source = std::fs::read_to_string(tree.join("runtime/ipaddr_stdlib.rb")).unwrap();
    assert!(source.contains("require \"ipaddr\""));
    assert!(!source.contains("def initialize"), "adapter overwrites bundled class");
    // Default machine-integer consumers still receive the existing octet
    // port. This profile explicitly chooses the complete package instead.
    assert!(std::fs::read_to_string(tree.join("runtime/ipaddr.rb")).unwrap().contains("def initialize"));
    std::fs::copy(tree.join("runtime/ipaddr_stdlib.rb"), tree.join("runtime/ipaddr.rb")).unwrap();
    std::fs::remove_file(tree.join("runtime/ipaddr.rbs")).unwrap();
    tree
}

#[test]
fn emitted_ipaddr_offers_explicit_bundled_provider_without_changing_default() {
    tree();
}

#[test]
#[ignore = "requires Spinel toolchain and CRuby stdlib; no network"]
fn emitted_ipaddr_string_case_equality_and_octets_match_cruby() {
    let tree = tree();
    let probe = r##"require_relative "runtime/ipaddr"
require "ipaddr" # The order must not produce a second, incompatible IPAddr.
nets = [IPAddr.new("0.0.0.0/0"), IPAddr.new("::/0")]
raise "IPv4 case equality" unless nets[0] === "127.0.0.1"
raise "IPv6 case equality" unless nets[1] === "2001:db8::1"
raise "cross-family inclusion" if nets[0] === "::1"
raise "string include" unless IPAddr.new("10.0.0.0/8").include?("10.1.2.3")
raise "object include" unless IPAddr.new("10.0.0.0/8").include?(IPAddr.new("10.1.2.3"))
raise "outside subnet" if IPAddr.new("10.0.0.0/8") === "11.1.2.3"
raise "v4 octets adapter" unless IPAddr.new("10.1.2.3/8").octets == [10, 0, 0, 0]
raise "v6 octets adapter" unless IPAddr.new("::1").octets == [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 1]
rejected = false
begin
  nets[0] === "not-an-ip.invalid"
rescue IPAddr::InvalidAddressError
  rejected = true
end
raise "invalid address accepted" unless rejected
puts "bundled IPAddr case equality, string/object inclusion, masked octets: OK"
"##;
    std::fs::write(tree.join("ipaddr_probe.rb"), probe).unwrap();
    let run = |command: &mut Command| {
        let out = command.current_dir(&*tree).output().expect("run IPAddr probe");
        assert!(out.status.success(), "{command:?}: {}\n{}\n{}", out.status,
            String::from_utf8_lossy(&out.stdout), String::from_utf8_lossy(&out.stderr));
        out.stdout
    };
    run(Command::new(std::env::var("SPINEL").unwrap_or_else(|_| "spinel".into()))
        .args(["--jobs=4", "--int-overflow=promote", "ipaddr_probe.rb", "-o", "ipaddr_probe"]));
    let native = run(&mut Command::new(tree.join("ipaddr_probe")));
    let ruby = run(Command::new("ruby").args(["--enable-frozen-string-literal", "ipaddr_probe.rb"]));
    assert_eq!(native, ruby);
    assert_eq!(native, b"bundled IPAddr case equality, string/object inclusion, masked octets: OK\n");
}

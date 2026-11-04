#!/usr/bin/env python3
"""Original GlobalSetting dependency proofs, NOT ticket019 or Rails boot.

Default: register + actual EnvProvider. --cache: original configure!, complete
providers, original defaults resource and cached getters. No SiteSetting/YAML/
plugin/security/PG/cache-service bootstrap is replaced or claimed. Test ENV and
configuration-file writes stay in owned disposable processes/files, not Valkey.
"""
from __future__ import annotations
import json
import sys
import shutil
from pathlib import Path
from verify import HERE, ROOT, Run, digest, equal_records

CONSUMER = '''# Synthetic TEST caller; all factory/provider/coerce bodies are original.
class GlobalRegisterProbe
  #: (String input, (Integer | bool | String | nil) default) -> Array[Integer | bool | String | nil]
  def self.exercise(input, default)
    GlobalSetting.provider = GlobalSetting::EnvProvider.new
    name = input.to_sym
    raise "present before original register" if GlobalSetting.respond_to?(name, true)
    installed = GlobalSetting.register(name, default)
    raise "original registration result" unless installed == name
    raise "missing after original register" unless GlobalSetting.respond_to?(name)
    first = GlobalSetting.public_send(name)
    ENV["DISCOURSE_" + input.upcase] = "17"
    second = GlobalSetting.public_send(name)
    [first.class.name, first, second.class.name, second]
  end
end
'''
ENTRY = '''# frozen_string_literal: true
require_relative "emitted/runtime/active_support_ext"
require_relative "emitted/runtime/json_builder"
require_relative "emitted/app/models"
default = case ARGV.fetch(1)
when "false" then false
when "zero" then 0
when "empty" then ""
when "text" then "fallback"
else nil
end
puts JsonBuilder.encode_value(GlobalRegisterProbe.exercise(ARGV.fetch(0), default))
'''


def audit(app: Path) -> None:
    maps = json.loads((app / "projection-map.json").read_text())
    assert 1 <= len(maps) <= 2
    for item in maps:
        source = (HERE / "source/discourse" / item["source"]).read_bytes()
        generated = (app / item["generated"]).read_bytes()
        assert digest(source) == item["source_sha256"]
        assert digest(generated) == item["generated_sha256"]
        if item.get("role") == "complete_original_resource":
            assert generated == source
            continue
        covered = set()
        for span in item["selected_spans"]:
            start, end = span["start_byte"], span["end_byte"]
            assert generated[start:end] == source[start:end]
            assert digest(source[start:end]) == span["text_sha256"]
            covered.update(range(start, end))
        assert len(source) == len(generated)
        assert all(index in covered or byte in (32, 10) for index, byte in enumerate(generated))


CACHE_CONSUMER = '''class GlobalCacheProbe
  #: (String input, String path, bool blank) -> Array[Integer | bool | String | nil]
  def self.exercise(input, path, blank)
    GlobalSetting.configure!(path: path, use_blank_provider: blank)
    name = input.to_sym
    fallback = (input + "_fallback").to_sym
    GlobalSetting.add_default(fallback, 23)
    raise "original add_default" unless GlobalSetting.public_send(fallback) == 23
    GlobalSetting.load_defaults
    first = GlobalSetting.public_send(name)
    ENV["DISCOURSE_" + input.upcase] = "17"
    second = GlobalSetting.public_send(name)
    # Original register deliberately replaces the cached event with a live lookup.
    GlobalSetting.register(name, 19)
    third = GlobalSetting.public_send(name)
    [first.class.name, first, second.class.name, second, third.class.name, third]
  end
end
'''


def verify_cache(run: Run, app: Path, emitted: Path) -> int:
    """Original configure/load_defaults/provider event closure, not Rails boot."""
    run.env["ROUNDHOUSE_ORIGINAL_GLOBAL_SETTING_APP"] = str(app)
    try:
        run.command("closed-original-ir", ["cargo", "test", "--test", "runtime_definition_computed_cache", "original_factory_templates_have_closed_types", "--", "--ignored"], cwd=ROOT / "roundhouse")
    finally:
        del run.env["ROUNDHOUSE_ORIGINAL_GLOBAL_SETTING_APP"]
    resource = "config/discourse_defaults.conf"
    data = (HERE / "source/discourse" / resource).read_bytes()
    assert b"<%" not in data, "the actual native ERB.result library refuses eval tags"
    assert (app / resource).read_bytes() == data
    # Packaging an original resource is not freezing a getter: all three run
    # the original parser, and per-case config files are created AFTER compile.
    shutil.copyfile(app / resource, emitted / resource)
    entry = ENTRY[:ENTRY.index("default = case")] + '''begin
  result = GlobalCacheProbe.exercise(ARGV.fetch(0), ARGV.fetch(1), ARGV.fetch(2) == "blank")
  puts JsonBuilder.encode_value(result)
rescue NameError
  puts JsonBuilder.encode_value(["NameError"])
end
'''
    reference = entry.replace('require_relative "emitted/runtime/active_support_ext"\nrequire_relative "emitted/runtime/json_builder"\nrequire_relative "emitted/app/models"',
                              'require "erb"\nrequire "json"\nrequire "active_support/core_ext/object/blank"\nrequire_relative "input/app/models/global_setting"\nrequire_relative "input/app/models/global_register_probe"').replace("JsonBuilder.encode_value(", "JSON.generate(")
    (run.path / "entry.rb").write_text(entry)
    (run.path / "reference.rb").write_text(reference)
    run.command("native-compile", [ROOT / "spinel/spinel", "--jobs=4", "--rbs", emitted, run.path / "entry.rb", "-o", run.path / "probe"])
    assert (run.path / "probe").read_bytes()[:4] == b"\x7fELF"
    observations = []
    cases = [("env", value) for value in ("true", "false", "0", "-29", "hello", "")]
    cases += [("file", value) for value in ("37", "", "abc# quoted")]
    cases += [("blank", None), ("defaults", None), ("invalid-name", "1")]
    for index, (provider, value) in enumerate(cases):
        name = "hostname" if provider in ("blank", "defaults") else "fidelity_cache_source_" + str(701 + index)
        if provider == "invalid-name":
            name = "fidelity-invalid-cache-source"
        key = "DISCOURSE_" + name.upper()
        run.env.pop(key, None)
        path = run.path / "missing-config.conf"
        if provider == "file":
            path = run.path / f"runtime-config-{index}.conf"
            path.write_text(f'{name} = "{value}"\n')
        elif value is not None:
            run.env[key] = value
        outputs = {}
        for kind, command in (("native", [run.path / "probe"]), ("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "entry.rb"]),
                              ("original", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "reference.rb"])):
            label = f"{kind}-{index}"
            _, output = run.command(label, ["strace", "-f", "-e", "trace=execve,connect,openat", "-o", run.path / f"{label}.trace", *command, name, path, provider], cwd=run.path, timeout=60)
            outputs[kind] = json.loads(output)
            trace = (run.path / f"{label}.trace").read_text()
            assert "connect(" not in trace, f"unexpected network in {label}"
            assert "discourse_defaults.conf" in trace, "original defaults resource was not read"
            if provider == "file":
                assert path.name in trace, "runtime provider config not read"
            if kind == "native":
                assert trace.count("execve(") == 1, "native spawned a child"
        equal_records(outputs["native"], outputs["compat"])
        equal_records(outputs["native"], outputs["original"])
        result = outputs["native"]
        if provider == "invalid-name":
            equal_records(result, ["NameError"])
        else:
            equal_records(result[:2], result[2:4])
            if provider == "env":
                expected = {"true": True, "false": False, "0": 0, "-29": -29, "hello": "hello", "": None}[value]
                equal_records([result[1], result[5]], [expected, 17])
            elif provider == "file":
                expected = {"37": 37, "": None, "abc# quoted": "abc# quoted"}[value]
                equal_records([result[1], result[5]], [expected, expected])
            elif provider == "blank":
                equal_records([result[5]], [19])
            else:
                equal_records([result[5]], [17])
        observations.append(dict(provider=provider, name=name, initial_input=value, observed=result))
    audit(app)
    run.provenance()
    assert (emitted / resource).read_bytes() == data
    run.evidence.update(status="passed_original_global_cache_source_closure_only", observations=observations,
                        native_elf_sha256=digest((run.path / "probe").read_bytes()),
                        original_resource_sha256=digest(data), actual_runtime_resource_reads=True,
                        original_factory_methods=["register", "add_default", "configure!", "load_defaults"],
                        complete_original_providers=["BaseProvider", "EnvProvider", "FileProvider", "BlankProvider"],
                        same_lowered_ruby={str(p.relative_to(emitted)): digest(p.read_bytes()) for p in sorted(emitted.rglob("*.rb"))},
                        unsupported_application_body_rewrites=[], network_connections=0,
                        limitation="Original selected factory/provider/resource closure ONLY; NOT full GlobalSetting class/Rails boot, SiteSetting/YAML/plugin/User/security/PG/cache-service bootstrap or019 acceptance")
    print(f"PASS original GlobalSetting configure/load_defaults/cache source closure ONLY, NOT019: {run.path}")
    return 0


def main() -> int:
    cache = sys.argv[1:] == ["--cache"]
    assert cache or not sys.argv[1:], "usage: verify_global_setting_register.py [--cache]"
    run = Run("verify-global-cache-source" if cache else "verify-global-register-pure")
    try:
        run.provenance()
        app = run.path / "input"
        app.mkdir()
        run.command("project", ["bundle", "exec", "ruby", HERE / "tools/project_global_setting_register.rb", HERE / "source/discourse", app, "cache" if cache else "register"])
        for path, text in {
            "db/schema.rb": "ActiveRecord::Schema.define do\nend\n",
            "config/routes.rb": "Rails.application.routes.draw do\nend\n",
            "app/models/global_register_probe.rb": CACHE_CONSUMER if cache else CONSUMER,
        }.items():
            target = app / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        audit(app)
        run.command("roundhouse-build", ["cargo", "build", "--release", "--bin", "roundhouse"], cwd=ROOT / "roundhouse")
        run.command("emit", [ROOT / "roundhouse/target/release/roundhouse", "--target", "spinel", app, "-o", run.path / "emitted"])
        emitted = run.path / "emitted"
        assert "define_singleton_method" not in (emitted / "app/models/global_setting.rb").read_text()
        assert "RoundhouseRuntimeFamily" in (emitted / "app/models/global_setting.rb").read_text()
        if cache:
            run.evidence.update(projection_map="input/projection-map.json", stage="Original GlobalSetting factory/provider/resource source closure ONLY", consumer_sha256=digest(CACHE_CONSUMER.encode()))
            return verify_cache(run, app, emitted)
        run.evidence.update(projection_map="input/projection-map.json", stage="PURE original GlobalSetting.register + actual EnvProvider/coerce ONLY",
                            unsupported_application_body_rewrites=[], consumer_sha256=digest(CONSUMER.encode()))
        run.evidence["same_lowered_ruby"] = {str(p.relative_to(emitted)): digest(p.read_bytes()) for p in sorted(emitted.rglob("*.rb"))}
        (run.path / "entry.rb").write_text(ENTRY)
        reference = ENTRY.replace('require_relative "emitted/runtime/active_support_ext"\nrequire_relative "emitted/runtime/json_builder"\nrequire_relative "emitted/app/models"',
                                  'require "active_support/core_ext/object/blank"\nrequire "json"\nrequire_relative "input/app/models/global_setting"\nrequire_relative "input/app/models/global_register_probe"').replace("puts JsonBuilder.encode_value(", "puts JSON.generate(")
        assert reference != ENTRY
        (run.path / "reference.rb").write_text(reference)
        run.command("native-compile", [ROOT / "spinel/spinel", "--jobs=4", "--rbs", emitted, run.path / "entry.rb", "-o", run.path / "probe"])
        assert (run.path / "probe").read_bytes()[:4] == b"\x7fELF"
        run.evidence["native_elf_sha256"] = digest((run.path / "probe").read_bytes())
        cases = [(None, "false", None), (None, "zero", 0), (None, "empty", None), (None, "text", "fallback"),
                 (None, "nil", None), ("true", "nil", True), ("false", "text", False), ("29", "nil", 29),
                 ("hello", "zero", "hello"), ("", "text", None)]
        observations = []
        for index, (environment, default, expected) in enumerate(cases):
            name = "fidelity_runtime_provider_" + str(701 + index)
            key = "DISCOURSE_" + name.upper()
            run.env.pop(key, None)
            if environment is not None:
                run.env[key] = environment
            outputs = {}
            for kind, command in (("native", [run.path / "probe"]), ("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "entry.rb"]),
                                  ("original", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "reference.rb"])):
                label = f"{kind}-{index}"
                _, output = run.command(label, ["strace", "-f", "-e", "trace=execve,connect", "-o", run.path / f"{label}.trace", *command, name, default], cwd=run.path, timeout=60)
                outputs[kind] = json.loads(output)
                trace = (run.path / f"{label}.trace").read_text()
                assert "connect(" not in trace, f"unexpected network in {label}"
                if kind == "native":
                    assert trace.count("execve(") == 1, "native spawned a child"
            equal_records(outputs["native"], outputs["compat"])
            equal_records(outputs["native"], outputs["original"])
            equal_records([outputs["native"][1], outputs["native"][3]], [expected, 17])
            observations.append(dict(input_name=name, initial_env=environment, default_kind=default, observed=outputs["native"]))
        # This is a TYPE/provider dependency negative, not category security.
        try:
            equal_records([True], [1])
        except AssertionError:
            pass
        else:
            raise AssertionError("typed comparator accepted bool as integer")
        audit(app)
        run.provenance()
        assert run.evidence["same_lowered_ruby"] == {str(p.relative_to(emitted)): digest(p.read_bytes()) for p in sorted(emitted.rglob("*.rb"))}
        run.evidence.update(status="passed_pure_original_register_only", observations=observations, network_connections=0,
                            typed_negative_control="bool-vs-int rejected", reference="Unlowered byte-exact original methods with actual bundled ActiveSupport, not Rails boot",
                            limitation="NOT configure/load_defaults/YAML/plugin/SiteSetting/cache/User/security/PG/bootstrap or strict019 acceptance")
        print(f"PASS pure original register/provider ONLY, NOT ticket019: {run.path}")
        return 0
    except Exception as error:
        run.evidence.update(status="failed", error=str(error))
        print(f"NOT PASSED: {error}; evidence {run.path}")
        return 1
    finally:
        run.save()


if __name__ == "__main__":
    raise SystemExit(main())

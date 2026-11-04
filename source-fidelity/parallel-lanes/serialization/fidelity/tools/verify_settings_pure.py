#!/usr/bin/env python3
"""Pure original settings dependencies, NOT settings boot or ticket019 acceptance.

No oracle or external services run here. Fixtures are synthetic YAML/default
values for isolated original methods, never a production settings snapshot.
The full pinned production YAML resource is also parsed by the unchanged
original loader and compared record-for-record, NOT installed as settings.
"""
from __future__ import annotations

import json
from pathlib import Path

from verify import HERE, ROOT, Run, digest, equal_records


PROBE = '''# frozen_string_literal: true
require "yaml"
require "set"
require_relative "emitted/runtime/active_support_ext"
require_relative "emitted/app/models"
yaml = PureYamlConsumer.new(ENV.fetch("FIDELITY_PURE_YAML")).read
raise "YAML false" unless yaml["values"]["toggle"] == false
raise "YAML zero type" unless yaml["values"]["count"].is_a?(Integer)
raise "YAML zero" unless yaml["values"]["count"] == 0
raise "YAML empty" unless yaml["values"]["text"] == ""
raise "YAML nil" unless yaml["values"]["absent"].nil?
raise "YAML aliases" unless yaml["alias"]["count"] == 0
# No service object is needed by these ORIGINAL pure methods. This is not a
# SiteSetting instance or a substitute provider/getter/plugin implementation.
defaults = SiteSettings::DefaultsProvider.new(nil)
defaults.load_setting("pure_toggle", false, nil)
defaults.load_setting("pure_count", 0, nil)
defaults.load_setting("pure_text", "", { "fr" => "bonjour" })
raise "default false" unless defaults.all_clean[:pure_toggle] == false
raise "default zero" unless defaults.all_clean[:pure_count] == 0
raise "default empty" unless defaults.all_clean[:pure_text] == ""
raise "locale override" unless defaults.all_clean("fr")[:pure_text] == "bonjour"
raise "locale fallback" unless defaults.all_clean("fr")[:pure_toggle] == false
raise "unknown locale fallback" unless defaults.all_clean("de")[:pure_count] == 0
copy = defaults.all_clean
copy[:pure_count] = 99
raise "copied defaults" unless defaults.all_clean[:pure_count] == 0
raise "setting membership" unless defaults.has_setting?(:pure_toggle)
raise "default locale membership" unless defaults.has_setting?(:default_locale)
raise "missing membership" if defaults.has_setting?(:missing)
loaded = SiteSettings::DefaultsProvider.new(nil)
SiteSettings::YamlLoader.new(ENV.fetch("FIDELITY_PURE_DECLARATIONS")).load do |category, name, value, metadata|
  raise "original category" unless category == "pure"
  if name == "loaded_count"
    raise "symbolized metadata" unless metadata[:min] == 0
  end
  loaded.load_setting(name, value, nil)
end
raise "loaded false" unless loaded.all_clean[:loaded_toggle] == false
raise "loaded zero" unless loaded.all_clean[:loaded_count] == 0
raise "loaded empty" unless loaded.all_clean[:loaded_text] == ""
%w[FIDELITY_PURE_MISSING_DEFAULT FIDELITY_PURE_VALIDATOR_CONFLICT].each do |key|
  caught = false
  begin
    SiteSettings::YamlLoader.new(ENV.fetch(key)).load do |category, name, value, metadata|
      raise "invalid declaration yielded"
    end
  rescue StandardError => error
    expected = key == "FIDELITY_PURE_MISSING_DEFAULT" ? "missing default value" : "validation ignored"
    raise "wrong original validation error" unless error.message.include?(expected)
    caught = true
  end
  raise "missing original validation error" unless caught
end
raise "deliberately wrong TEST expectation" if ENV["FIDELITY_PURE_WRONG"] == "1" && defaults.all_clean[:pure_toggle] != true
puts "pure original YAML and defaults PASS"
require_relative "emitted/runtime/json_builder"
# JSON object keys alone cannot distinguish String from Symbol. Observe
# every nested metadata key kind as well, without replacing loader behavior.
def fidelity_metadata_key_classes(node)
  classes = []
  if node.is_a?(Hash)
    node.each do |key, value|
      classes << key.class.name
      classes.concat(fidelity_metadata_key_classes(value))
    end
  elsif node.is_a?(Array)
    node.each { |value| classes.concat(fidelity_metadata_key_classes(value)) }
  end
  classes
end
original_rows = []
SiteSettings::YamlLoader.new(ENV.fetch("FIDELITY_FULL_ORIGINAL_SETTINGS_YAML")).load do |category, name, value, metadata|
  original_rows << [category, name, value.class.name, value, metadata, fidelity_metadata_key_classes(metadata)]
end
puts JsonBuilder.encode_value(original_rows)
'''


def audit_projection(app: Path):
    for item in json.loads((app / "projection-map.json").read_text()):
        source = (HERE / "source/discourse" / item["source"]).read_bytes()
        projected = (app / item["generated"]).read_bytes()
        assert len(source) == len(projected)
        assert digest(source) == item["source_sha256"]
        assert digest(projected) == item["generated_sha256"]
        covered = bytearray(len(source))
        for span in item["selected_spans"]:
            start, end = span["start_byte"], span["end_byte"]
            assert source[start:end] == projected[start:end]
            assert digest(source[start:end]) == span["text_sha256"]
            covered[start:end] = b"1" * (end - start)
        assert all(covered[i] or byte in (32, 10) for i, byte in enumerate(projected))


def main():
    run = Run("verify-settings-pure")
    run.evidence["stage"] = "PURE original dependency subset; NOT settings boot, Rails parity or ticket019 acceptance"
    # These methods have no networking. Trace both runs and reject connections.
    run.env.update(DATABASE_URL="sqlite3::memory:", REDIS_URL="redis://127.0.0.1:1/0",
                   DISCOURSE_REDIS_PORT="1", BLOG_DB=":memory:")
    try:
        run.provenance()
        app = run.path / "input"
        run.command("project", ["ruby", HERE / "tools/project_settings_pure.rb", HERE / "source/discourse", app])
        for path, text in {
            "db/schema.rb": "ActiveRecord::Schema.define do\nend\n",
            "config/routes.rb": "Rails.application.routes.draw do\nend\n",
            "app/models/pure_yaml_consumer.rb": '''# Synthetic TEST consumer of the original private YAML method.
class PureYamlConsumer < SiteSettings::YamlLoader
  def read
    load_yaml(@file)
  end
end
''',
        }.items():
            target = app / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        fixture = run.path / "pure.yml"
        fixture.write_text('values: &values\n  toggle: false\n  count: 0\n  text: ""\n  absent: null\nalias: *values\n')
        run.env["FIDELITY_PURE_YAML"] = str(fixture)
        original_resource = HERE / "source/discourse/config/site_settings.yml"
        original_resource_sha = digest(original_resource.read_bytes())
        run.env["FIDELITY_FULL_ORIGINAL_SETTINGS_YAML"] = str(original_resource)
        declarations = run.path / "declarations.yml"
        declarations.write_text('pure:\n  loaded_toggle: false\n  loaded_count:\n    default: 0\n    min: 0\n  loaded_text:\n    default: ""\n')
        run.env["FIDELITY_PURE_DECLARATIONS"] = str(declarations)
        for key, name, text in (
            ("FIDELITY_PURE_MISSING_DEFAULT", "missing.yml", "pure:\n  missing:\n    default: null\n"),
            ("FIDELITY_PURE_VALIDATOR_CONFLICT", "conflict.yml", "pure:\n  conflict:\n    default: 0\n    min: 0\n    validator: TestValidator\n"),
        ):
            fixture_path = run.path / name
            fixture_path.write_text(text)
            run.env[key] = str(fixture_path)
        run.command("roundhouse-build", ["cargo", "build", "--bin", "roundhouse"], cwd=ROOT / "roundhouse")
        audit_projection(app)
        run.command("emit", [ROOT / "roundhouse/target/debug/roundhouse", "--target", "spinel", app, "-o", run.path / "emitted"])
        run.evidence["projection_map"] = "input/projection-map.json"
        run.evidence["same_lowered_ruby"] = {str(p.relative_to(run.path / "emitted")): digest(p.read_bytes())
                                            for p in sorted((run.path / "emitted").rglob("*.rb"))}
        (run.path / "entry.rb").write_text(PROBE)
        run.evidence["consumer_sha256"] = digest(PROBE.encode())
        run.command("native-compile", [ROOT / "spinel/spinel", "--rbs", run.path / "emitted", run.path / "entry.rb", "-o", run.path / "probe"])
        assert (run.path / "probe").read_bytes()[:4] == b"\x7fELF"
        run.evidence["native_elf_sha256"] = digest((run.path / "probe").read_bytes())
        reference = PROBE.replace(
            'require_relative "emitted/runtime/active_support_ext"\nrequire_relative "emitted/app/models"',
            'require "active_support/core_ext/object/blank"\nrequire "active_support/core_ext/hash/keys"\n'
            'require_relative "input/app/models/yaml_loader"\n'
            'require_relative "input/app/models/defaults_provider"\n'
            'require_relative "input/app/models/pure_yaml_consumer"',
        )
        reference = reference.replace('require_relative "emitted/runtime/json_builder"', 'require "json"').replace("JsonBuilder.encode_value(", "JSON.generate(")
        assert reference != PROBE
        (run.path / "reference.rb").write_text(reference)
        full_resource_records = {}
        for name, command in (("native", [run.path / "probe"]),
                              ("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "entry.rb"]),
                              ("original-library-reference", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "reference.rb"])):
            _, output = run.command(name, ["strace", "-f", "-e", "trace=execve,connect,openat", "-o", run.path / f"{name}.trace", *command], cwd=run.path, timeout=60)
            marker, separator, records = output.partition("\n")
            assert marker + separator == "pure original YAML and defaults PASS\n", output
            full_resource_records[name] = json.loads(records)
            assert full_resource_records[name], "full original resource yielded nothing"
            trace = (run.path / f"{name}.trace").read_text()
            assert "connect(" not in trace, f"unexpected network connection in {name}"
            assert str(original_resource) in trace, "original YAML was not actually read"
            if name == "native":
                assert trace.count("execve(") == 1, "native spawned another process"
        equal_records(full_resource_records["native"], full_resource_records["compat"])
        equal_records(full_resource_records["native"], full_resource_records["original-library-reference"])
        assert digest(original_resource.read_bytes()) == original_resource_sha
        run.evidence["complete_original_yaml_resource"] = {
            "source": "config/site_settings.yml", "sha256": original_resource_sha,
            "records": len(full_resource_records["native"]),
            "full_typed_value_and_metadata_parity": True,
            "nested_metadata_key_classes_compared": True,
            "runtime_file_read_traced": True,
            "limitation": "Original loader/production resource parse ONLY; no setting registration/getter/provider/cache-service boot"
        }
        run.env["FIDELITY_PURE_WRONG"] = "1"
        code, _ = run.command("native-wrong-expectation", [run.path / "probe"], cwd=run.path, check=False, timeout=60)
        assert code != 0
        assert "deliberately wrong TEST expectation" in (run.path / "native-wrong-expectation.stderr").read_text()
        audit_projection(app)
        run.provenance()
        after = {str(p.relative_to(run.path / "emitted")): digest(p.read_bytes())
                 for p in sorted((run.path / "emitted").rglob("*.rb"))}
        assert after == run.evidence["same_lowered_ruby"]
        run.evidence.update(status="passed_pure_subset_only", network_connections=0,
                            reference="Unlowered original pure projections with actual bundled ActiveSupport/Psych; NOT a Rails application boot",
                            limitation="DefaultsProvider#all/plugin modifiers/provider/upcoming changes and original settings declaration/getter remain unproved; native rekeying nested statically String-keyed literal containers explicitly refuses")
        print(f"PASS pure dependency subset ONLY, NOT ticket019: {run.path}")
        return 0
    except Exception as error:
        run.evidence.update(status="failed", error=str(error))
        print(f"NOT PASSED: {error}; evidence {run.path}")
        return 1
    finally:
        run.save()


if __name__ == "__main__":
    raise SystemExit(main())

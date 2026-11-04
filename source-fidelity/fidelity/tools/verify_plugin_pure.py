#!/usr/bin/env python3
"""Original in-memory modifier dispatch, not production plugin/settings proof.

Use REAL projected Plugin::Instance bodies, never an enabled? stub. Only an
unconfigured plugin (no enabled_site_setting) is exercised. Registered callbacks
are test blocks; no production registry is replaced, read or suppressed.
"""
from __future__ import annotations

import json
from verify import HERE, ROOT, Run, digest
from verify_settings_pure import audit_projection

PROBE = '''# frozen_string_literal: true
require "set"
require_relative "emitted/app/models/plugin/instance"
require_relative "emitted/app/models/discourse_plugin_registry"
require_relative "emitted/app/models/site_settings/defaults_provider"
require_relative "emitted/app/models/upcoming_metadata_fixture"
plugin = Plugin::Instance.new
if ENV["FIDELITY_PURE_CONFIGURED"] == "1"
  plugin.enabled_site_setting(:pure_unavailable_setting)
  plugin.enabled?
  raise "configured setting branch unexpectedly available"
end
raise "original unconfigured enabled predicate" unless plugin.enabled?
input = { count: 1 }
raise "unregistered identity" unless DiscoursePluginRegistry.apply_modifier(:absent, input).equal?(input)
trace = []
registered_late = false
DiscoursePluginRegistry.register_modifier(plugin, :pure_test) do |value, delta|
  trace << :add
  if !registered_late
    DiscoursePluginRegistry.register_modifier(plugin, :pure_test) do |late_value, late_delta|
      trace << :late
      late_value[:count] += 100
      late_value
    end
    registered_late = true
  end
  value[:count] += delta
  value
end
DiscoursePluginRegistry.register_modifier(plugin, :pure_test) do |value, delta|
  trace << :multiply
  value[:count] *= delta
  value
end
first = DiscoursePluginRegistry.apply_modifier(:pure_test, input, 2)
raise "registered callbacks identity" unless first.equal?(input)
raise "registered callbacks values" unless input[:count] == 6
raise "original length snapshot/order" unless trace == [:add, :multiply]
second = DiscoursePluginRegistry.apply_modifier(:pure_test, input, 2)
raise "next dispatch identity" unless second.equal?(input)
raise "next dispatch callbacks" unless input[:count] == 116
raise "late callback order" unless trace == [:add, :multiply, :add, :multiply, :late]
DiscoursePluginRegistry.register_modifier(plugin, :replacement) do |value, delta|
  { count: value[:count] + delta }
end
DiscoursePluginRegistry.register_modifier(plugin, :replacement) do |value, delta|
  value[:count] += delta
  value
end
replacement = DiscoursePluginRegistry.apply_modifier(:replacement, input, 2)
raise "callback return replacement" if replacement.equal?(input)
raise "replacement chain" unless replacement[:count] == 120 && input[:count] == 116
raise "integer callback values" unless replacement[:count].is_a?(Integer)
DiscoursePluginRegistry.register_modifier(plugin, :failure) do |value, delta|
  raise ArgumentError, "pure callback failure"
end
caught = false
begin
  DiscoursePluginRegistry.apply_modifier(:failure, input, 2)
rescue ArgumentError => error
  raise "wrong callback exception" unless error.message == "pure callback failure"
  caught = true
end
raise "callback exception was swallowed" unless caught
raise "missing register after initialization" unless DiscoursePluginRegistry.apply_modifier(:absent, input).equal?(input)
metadata = UpcomingMetadataFixture.new
defaults = SiteSettings::DefaultsProvider.new(metadata)
defaults.load_setting("pure_count", 1, nil)
defaults.load_setting("pure_disabled", false, nil)
defaults.load_setting("pure_text", "", { "fr" => "bonjour" })
# First select the original API's no-upcoming branch; modifier dispatch
# still runs. Then execute its normal branch using original metadata code.
before_modifiers = defaults.all("fr", include_upcoming_changes_overrides: false)
raise "all locale branch" unless before_modifiers[:pure_text] == "bonjour"
raise "all false" unless before_modifiers[:pure_disabled] == false
DiscoursePluginRegistry.register_modifier(plugin, :site_setting_defaults) do |values|
  values[:pure_count] += 5
  values
end
modified = defaults.all("fr", include_upcoming_changes_overrides: false)
raise "original all modifier integration" unless modified[:pure_count] == 6
raise "modifier altered stored defaults" unless defaults.all_clean[:pure_count] == 1
raise "modifier retained false/string types" unless modified[:pure_disabled] == false && modified[:pure_text] == "bonjour"
metadata.upcoming_change_default_overrides[:pure_count] = { upcoming_change: :pure_feature, new_default: 20 }
raise "inactive override" unless defaults.all("fr")[:pure_count] == 6
defaults.activate_upcoming_change_override(:pure_feature)
raise "active override before modifier" unless defaults.all("fr")[:pure_count] == 25
raise "explicit override opt-out" unless defaults.all("fr", include_upcoming_changes_overrides: false)[:pure_count] == 6
defaults.deactivate_upcoming_change_override(:pure_feature)
raise "deactivated override" unless defaults.all("fr")[:pure_count] == 6
raise "stored default after override" unless defaults.all_clean[:pure_count] == 1
raise "deliberately wrong TEST modifier expectation" if ENV["FIDELITY_PURE_WRONG"] == "1" && input[:count] != 999
puts "original pure modifier callbacks PASS"
'''


def main():
    run = Run("verify-plugin-pure")
    run.evidence["stage"] = "PURE modifier registration/dispatch with actual unconfigured plugin; NOT production plugin/settings/019 proof"
    run.env.update(DATABASE_URL="sqlite3::memory:", REDIS_URL="redis://127.0.0.1:1/0", DISCOURSE_REDIS_PORT="1")
    try:
        run.provenance()
        app = run.path / "input"
        run.command("project", ["ruby", HERE / "tools/project_plugin_pure.rb", HERE / "source/discourse", app])
        for path, text in {"db/schema.rb": "ActiveRecord::Schema.define do\nend\n",
                           "config/routes.rb": "Rails.application.routes.draw do\nend\n",
                           "app/models/upcoming_metadata_fixture.rb": '''# Synthetic TEST consumer. Borrow the ORIGINAL metadata method, not a
# SiteSetting value getter or replacement service. No extend event occurs,
# so no SiteSettingExtension.extended hook is skipped or suppressed.
class UpcomingMetadataFixture
  def self.borrow(mod, name)
    define_method(name, mod.instance_method(name))
  end
  borrow SiteSettingExtension, :upcoming_change_default_overrides
end
''',
                           }.items():
            target = app / path
            target.parent.mkdir(parents=True, exist_ok=True)
            target.write_text(text)
        audit_projection(app)
        run.command("roundhouse-build", ["cargo", "build", "--bin", "roundhouse"], cwd=ROOT / "roundhouse")
        run.command("emit", [ROOT / "roundhouse/target/debug/roundhouse", "--target", "spinel", app, "-o", run.path / "emitted"])
        hashes = {str(p.relative_to(run.path / "emitted")): digest(p.read_bytes()) for p in sorted((run.path / "emitted").rglob("*.rb"))}
        run.evidence.update(projection_map="input/projection-map.json", same_lowered_ruby=hashes, consumer_sha256=digest(PROBE.encode()))
        (run.path / "entry.rb").write_text(PROBE)
        run.command("native-compile", [ROOT / "spinel/spinel", "--rbs", run.path / "emitted", run.path / "entry.rb", "-o", run.path / "probe"])
        assert (run.path / "probe").read_bytes()[:4] == b"\x7fELF"
        run.evidence["native_elf_sha256"] = digest((run.path / "probe").read_bytes())
        original = PROBE.replace('require_relative "emitted/app/models/plugin/instance"',
                                 'require_relative "input/app/models/plugin"\nrequire_relative "input/app/models/plugin/instance"')
        original = original.replace('require_relative "emitted/app/models/upcoming_metadata_fixture"',
                                    'require_relative "input/app/models/site_setting_extension"\nrequire_relative "input/app/models/upcoming_metadata_fixture"')
        original = original.replace('require_relative "emitted/app/models/', 'require_relative "input/app/models/')
        assert original != PROBE
        (run.path / "reference.rb").write_text(original)
        for name, command in (("native", [run.path / "probe"]),
                              ("compat", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "entry.rb"]),
                              ("original-reference", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "reference.rb"])):
            _, output = run.command(name, ["strace", "-f", "-e", "trace=execve,connect", "-o", run.path / f"{name}.trace", *command], cwd=run.path, timeout=60)
            assert output == "original pure modifier callbacks PASS\n", output
            trace = (run.path / f"{name}.trace").read_text()
            assert "connect(" not in trace, f"unexpected network connection: {name}"
            if name == "native":
                assert trace.count("execve(") == 1
        run.env["FIDELITY_PURE_WRONG"] = "1"
        code, _ = run.command("native-wrong-expectation", [run.path / "probe"], cwd=run.path, check=False, timeout=60)
        assert code != 0
        assert "deliberately wrong TEST modifier expectation" in (run.path / "native-wrong-expectation.stderr").read_text()
        del run.env["FIDELITY_PURE_WRONG"]
        run.env["FIDELITY_PURE_CONFIGURED"] = "1"
        try:
            for name, command in (("native-configured-unsupported", [run.path / "probe"]),
                                  ("reference-configured-unsupported", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", run.path / "reference.rb"])):
                code, _ = run.command(name, command, cwd=run.path, check=False, timeout=60)
                assert code != 0
                diagnostic = (run.path / f"{name}.stderr").read_text()
                assert "NameError" in diagnostic and "SiteSetting" in diagnostic
        finally:
            del run.env["FIDELITY_PURE_CONFIGURED"]
        audit_projection(app)
        run.provenance()
        assert hashes == {str(p.relative_to(run.path / "emitted")): digest(p.read_bytes()) for p in sorted((run.path / "emitted").rglob("*.rb"))}
        run.evidence.update(status="passed_pure_subset_only", network_connections=0,
                            defaults_provider_branch="Original #all/activate/deactivate execute default and explicit opt-out branches; original upcoming metadata method borrowed by TEST service (no extend event), with synthetic metadata; real SiteSetting service remains unproved",
                            metadata_fixture="Existing generic define_method(name, mod.instance_method(name)) expansion copies the original metadata body; no handwritten value getter, production snapshot or extended hook suppression",
                            configured_plugin_boundary="Real enabled_site_setting API reaches an explicit SiteSetting NameError under native/unlowered projection; NOT configured plugin support",
                            native_warning="SiteSetting declaration-only input is not loaded by this pure consumer; compiler warning is retained and configured failure is tested",
                            limitation="No configured enabled setting, disabled-plugin path, production plugin set/startup, actual SiteSetting service or native settings getter proof. No stubs/redefinitions of original plugin predicates/callbacks.")
        print(f"PASS pure modifier subset ONLY, NOT ticket019: {run.path}")
        return 0
    except Exception as error:
        run.evidence.update(status="failed", error=str(error))
        print(f"NOT PASSED: {error}; evidence {run.path}")
        return 1
    finally:
        run.save()


if __name__ == "__main__":
    raise SystemExit(main())

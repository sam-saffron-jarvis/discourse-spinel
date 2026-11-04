"""Original plugin predicate/registry projection, without services or stubs."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from verify_settings_pure import audit_projection


class PluginProjectionTest(unittest.TestCase):
    def test_real_predicate_and_dispatch_bodies_are_preserved(self):
        with tempfile.TemporaryDirectory(prefix="plugin-projection-", dir=HERE / "build") as temp:
            app = Path(temp)
            subprocess.run(["ruby", str(HERE / "tools/project_plugin_pure.rb"),
                            str(HERE / "source/discourse"), str(app)], check=True)
            audit_projection(app)
            instance = (app / "app/models/plugin/instance.rb").read_text()
            self.assertIn("def enabled?", instance)
            self.assertIn("@enabled_site_setting ? SiteSetting.get(@enabled_site_setting) : true", instance)
            self.assertIn("return false if !configurable?", instance)
            self.assertIn("def enabled_site_setting(setting = nil)", instance)
            self.assertNotIn("def register_anonymous_cache_key", instance)
            registry = (app / "app/models/discourse_plugin_registry.rb").read_text()
            self.assertIn("def self.register_modifier", registry)
            self.assertIn("arg = block.call(arg, *more_args) if plugin_instance.enabled?", registry)
            self.assertIn("length = registered_modifiers.length", registry)
            self.assertNotIn("def self.clear_modifiers!", registry)
            # Missing setting declaration remains missing, not a fabricated get.
            setting = (app / "app/models/site_setting.rb").read_text()
            self.assertIn("class SiteSetting < ActiveRecord::Base", setting)
            self.assertNotIn("def get", setting)
            self.assertNotIn("define_singleton_method", setting)
            defaults = (app / "app/models/site_settings/defaults_provider.rb").read_text()
            self.assertIn("def all(locale = nil, include_upcoming_changes_overrides: true)", defaults)
            self.assertIn("@site_setting.upcoming_change_default_overrides.each", defaults)
            self.assertIn("DiscoursePluginRegistry.apply_modifier(:site_setting_defaults, result)", defaults)
            metadata = (app / "app/models/site_setting_extension.rb").read_text()
            self.assertIn("def upcoming_change_default_overrides", metadata)
            self.assertIn("@upcoming_change_default_overrides ||= {}", metadata)
            self.assertNotIn("def self.extended", metadata)
            self.assertIn("def activate_upcoming_change_override", defaults)
            self.assertIn("def deactivate_upcoming_change_override", defaults)
            maps = json.loads((app / "projection-map.json").read_text())
            self.assertEqual(len(maps), 6)


if __name__ == "__main__":
    unittest.main()

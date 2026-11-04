"""File/provenance-only tests; never run the settings diagnostic output."""
import copy
from pathlib import Path
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
import settings_closure


class CompleteSettingsClosureTest(unittest.TestCase):
    def test_complete_bytes_and_boot_inventory_only(self):
        source = ROOT / "source/discourse"
        with tempfile.TemporaryDirectory(prefix="settings-closure-unit-", dir=ROOT / "build") as temp:
            output = Path(temp)
            manifest = settings_closure.materialize(source, output)
            self.assertEqual(len(manifest["files"]), 24)
            self.assertEqual({item["source"] for item in manifest["files"] if item["source"] in {
                "lib/upcoming_changes.rb", "lib/discourse.rb", "app/models/theme_site_setting.rb"
            }}, {"lib/upcoming_changes.rb", "lib/discourse.rb", "app/models/theme_site_setting.rb"})
            self.assertFalse(manifest["output_executed"])
            for item in manifest["files"]:
                self.assertEqual((source / item["source"]).read_bytes(), (output / item["generated"]).read_bytes())
            for path in settings_closure.BOOT_INVENTORY:
                self.assertFalse((output / path).exists())
            self.assertIn("GlobalSetting.configure!", (source / "config/application.rb").read_text())
            self.assertIn("GlobalSetting.load_defaults", (source / "config/application.rb").read_text())
            self.assertIn("SiteSetting.refresh!", (source / "config/initializers/005-site_settings.rb").read_text())
            corrupted = copy.deepcopy(manifest)
            corrupted["files"][0]["sha256"] = "0" * 64
            with self.assertRaises(AssertionError):
                settings_closure.audit(source, output, corrupted)
            first = output / manifest["files"][0]["generated"]
            first.write_bytes(first.read_bytes() + b"\n# changed\n")
            with self.assertRaises(AssertionError):
                settings_closure.audit(source, output, manifest)


if __name__ == "__main__":
    unittest.main()

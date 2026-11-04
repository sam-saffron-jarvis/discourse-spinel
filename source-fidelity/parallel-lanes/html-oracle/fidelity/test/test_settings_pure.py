"""Pure projection audit tests. No original settings boot or services."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from verify_settings_pure import audit_projection
from verify import digest


class SettingsProjectionTest(unittest.TestCase):
    def test_original_bytes_visibility_and_tamper_rejection(self):
        with tempfile.TemporaryDirectory(prefix="settings-projection-", dir=HERE / "build") as temp:
            app = Path(temp)
            subprocess.run(["ruby", str(HERE / "tools/project_settings_pure.rb"),
                            str(HERE / "source/discourse"), str(app)], check=True)
            audit_projection(app)
            maps_path = app / "projection-map.json"
            maps = json.loads(maps_path.read_text())
            loader = (app / "app/models/yaml_loader.rb").read_text()
            self.assertIn("yield category, setting_name, value, hash.deep_symbolize_keys!", loader)
            self.assertIn("private", loader)
            self.assertIn("YAML.load_file(path, aliases: true)", loader)
            defaults = (app / "app/models/defaults_provider.rb").read_text()
            self.assertNotIn("apply_modifier", defaults)
            self.assertNotIn("def get(", defaults)
            # Updating a generated-file digest cannot authorize extra code.
            target = app / maps[0]["generated"]
            original = target.read_bytes()
            target.write_bytes(b"x" + original[1:])
            maps[0]["generated_sha256"] = digest(target.read_bytes())
            maps_path.write_text(json.dumps(maps))
            with self.assertRaises(AssertionError):
                audit_projection(app)
            # Nor can it authorize editing any selected original byte.
            changed = bytearray(original)
            changed[maps[0]["selected_spans"][0]["start_byte"]] = ord("x")
            target.write_bytes(changed)
            maps[0]["generated_sha256"] = digest(changed)
            maps_path.write_text(json.dumps(maps))
            with self.assertRaises(AssertionError):
                audit_projection(app)


if __name__ == "__main__":
    unittest.main()

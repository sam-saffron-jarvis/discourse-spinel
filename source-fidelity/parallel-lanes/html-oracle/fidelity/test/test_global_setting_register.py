"""Audit original GlobalSetting source cuts; never boot settings or services."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from verify_global_setting_register import audit
from verify import digest


class GlobalSettingProjectionTest(unittest.TestCase):
    def test_both_modes_preserve_exact_factories_and_complete_providers(self):
        for mode in ("register", "cache"):
            with self.subTest(mode=mode), tempfile.TemporaryDirectory(prefix="global-projection-", dir=HERE / "build") as temp:
                app = Path(temp)
                subprocess.run(["ruby", str(HERE / "tools/project_global_setting_register.rb"),
                                str(HERE / "source/discourse"), str(app), mode], check=True)
                audit(app)
                maps_path = app / "projection-map.json"
                maps = json.loads(maps_path.read_text())
                roles = {span["role"] for span in maps[0]["selected_spans"]}
                methods = {"register", "add_default", "configure!", "load_defaults"} if mode == "cache" else {"register"}
                providers = {"BaseProvider", "EnvProvider", "FileProvider", "BlankProvider"} if mode == "cache" else {"BaseProvider", "EnvProvider"}
                self.assertEqual({role for role in roles if role.startswith("method:")}, {"method:self." + method for method in methods})
                self.assertEqual({role for role in roles if role.startswith("complete_nested_provider:")}, {"complete_nested_provider:" + provider for provider in providers})
                self.assertIn("original_provider_accessor", roles)
                # An updated digest cannot authorize changing a selected byte.
                target = app / maps[0]["generated"]
                original = target.read_bytes()
                changed = bytearray(original)
                changed[maps[0]["selected_spans"][0]["start_byte"]] = ord("x")
                target.write_bytes(changed)
                maps[0]["generated_sha256"] = digest(changed)
                maps_path.write_text(json.dumps(maps))
                with self.assertRaises(AssertionError):
                    audit(app)
                target.write_bytes(original)
                maps[0]["generated_sha256"] = digest(original)
                if mode == "cache":
                    resource = app / maps[1]["generated"]
                    resource.write_bytes(resource.read_bytes() + b"\n# unauthorized resource edit\n")
                    maps[1]["generated_sha256"] = digest(resource.read_bytes())
                    maps_path.write_text(json.dumps(maps))
                    with self.assertRaises(AssertionError):
                        audit(app)


if __name__ == "__main__":
    unittest.main()

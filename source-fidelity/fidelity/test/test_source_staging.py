"""Source acquisition/audit tests, never substitutes for activation proof."""
import copy
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
sys.path.insert(0, str(HERE / "tools"))
from framework_sources import verify_framework_sources
from archetype_dependency import materialize
from probe_original_query import audit_projection
from verify import digest


class SourceStagingTest(unittest.TestCase):
    def test_reduced_staging_shortcuts_are_rejected_semantically(self):
        result = subprocess.run(["ruby", str(HERE / "test/source_staging_semantics_test.rb")], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn("0 failures, 0 errors", result.stdout)

    def test_complete_original_dependency_files_are_not_fake_include_headers(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            app = Path(temp)
            maps = materialize(HERE, app, digest)
            self.assertEqual(audit_projection(app), maps)
            module = (app / "app/models/active_model/serialization.rb").read_bytes()
            original = (HERE / "source/framework/activemodel-8.1.4/lib/active_model/serialization.rb").read_bytes()
            self.assertEqual(module, original)
            self.assertIn(b"def serializable_hash(options = nil)", module)
            self.assertIn(b"def serializable_add_includes", module)
            self.assertIn(b'  register "regular"', (app / "app/models/archetype.rb").read_bytes())
            (app / "app/models/active_model/serialization.rb").write_bytes(module + b"\n")
            with self.assertRaises(AssertionError):
                audit_projection(app)

    def test_framework_pin_checks_original_package_members_and_rejects_tampering(self):
        lock = json.loads((HERE / "SOURCE_LOCK.json").read_text())
        reports = verify_framework_sources(lock, HERE, ROOT, digest)
        self.assertEqual(reports[0]["gem"], "activemodel")
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            isolated = Path(temp)
            for group in lock["framework_sources"]:
                for item in group["files"]:
                    destination = isolated / item["path"]
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    shutil.copyfile(HERE / item["path"], destination)
            item = lock["framework_sources"][0]["files"][0]
            target = isolated / item["path"]
            target.write_bytes(target.read_bytes() + b"\n")
            with self.assertRaises(AssertionError):
                verify_framework_sources(lock, isolated, ROOT, digest)
        changed = copy.deepcopy(lock)
        changed["framework_sources"][0]["package_sha256"] = "0" * 64
        with self.assertRaises(AssertionError):
            verify_framework_sources(changed, HERE, ROOT, digest)
        changed = copy.deepcopy(lock)
        changed["framework_sources"][0]["files"][0]["path"] = "../not-an-owned-source"
        with self.assertRaises(AssertionError):
            verify_framework_sources(changed, HERE, ROOT, digest)


if __name__ == "__main__":
    unittest.main()

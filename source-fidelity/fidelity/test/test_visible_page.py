import hashlib
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
import probe_visible_page


class VisiblePageTests(unittest.TestCase):
    def test_generation_is_reproducible_and_contains_original_operation_order(self):
        directory = HERE / "progressive/stage1"
        before = {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()}
        result = subprocess.run(["ruby", HERE / "tools/generate_visible_page.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()})
        manifest = json.loads((directory / "MANIFEST.json").read_text())
        self.assertFalse(manifest["complete_default_results_accepted"])
        self.assertFalse(manifest["full_query_accepted"])
        self.assertFalse(manifest["page_accepted"])
        self.assertFalse(manifest["live_values_used_as_inputs"])
        source = (HERE / "source/discourse" / manifest["source"]).read_bytes()
        expression = (directory / "original-expression.rb").read_bytes()
        positions = []
        for span in manifest["selected_statements"]:
            text = source[span["start_byte"]:span["end_byte"]]
            self.assertEqual(hashlib.sha256(text).hexdigest(), span["text_sha256"])
            positions.append(expression.index(text))
        self.assertEqual(positions, sorted(positions))
        self.assertTrue({822, 823, 826, 828, 834, 890, 905, 913, 914, 920}.issubset(
            {span["start_line"] for span in manifest["selected_statements"]}))

    def test_candidate_and_reference_expression_tampering_is_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage1"
            shutil.copytree(HERE / "progressive/stage1", target)
            with patch.object(probe_visible_page, "COMPONENT", target):
                run = probe_visible_page.VisiblePageRun()
                try:
                    run.provenance()
                    for name in ("topic_query_visible_page.rb", "original-expression.rb"):
                        path = target / name
                        original = path.read_bytes()
                        path.write_bytes(original.replace(b"result.visible", b"result.unscoped", 1))
                        with self.assertRaises(AssertionError):
                            run.provenance()
                        path.write_bytes(original)
                finally:
                    shutil.rmtree(run.path)

    def test_failed_commands_do_not_promote_stage_flags(self):
        run = probe_visible_page.VisiblePageRun()
        try:
            with patch.object(probe_visible_page.PortableSecurityRun, "command", side_effect=RuntimeError("native failed")):
                with self.assertRaises(RuntimeError):
                    run.command("native-compile", ["unused"])
            for flag in ("native_compile_ok", "native_query_executed", "stage_parity", "stage1_accepted",
                         "complete_default_results_accepted", "full_query_accepted", "page_accepted"):
                self.assertFalse(run.evidence[flag], flag)
        finally:
            shutil.rmtree(run.path)


if __name__ == "__main__":
    unittest.main()

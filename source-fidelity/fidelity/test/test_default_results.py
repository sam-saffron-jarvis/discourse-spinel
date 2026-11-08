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
import probe_default_results
import probe_visible_page


class DefaultResultsTests(unittest.TestCase):
    def test_generation_is_reproducible_and_every_cut_has_a_profile_guard(self):
        directory = HERE / "progressive/stage2"
        before = {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()}
        result = subprocess.run(["ruby", HERE / "tools/generate_default_results.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()})
        manifest = json.loads((directory / "MANIFEST.json").read_text())
        self.assertFalse(manifest["live_values_used_as_inputs"])
        self.assertFalse(manifest["full_query_accepted"])
        self.assertFalse(manifest["page_accepted"])
        self.assertEqual(len(manifest["guarded_branches"]), 8)
        source = (HERE / "source/discourse" / manifest["source"]).read_bytes()
        for span in [manifest["original_method"], *manifest["guarded_branches"], *manifest["dependencies"]]:
            text = source[span["start_byte"]:span["end_byte"]]
            self.assertEqual(hashlib.sha256(text).hexdigest(), span["text_sha256"])
        self.assertTrue(all(span["reason"] for span in manifest["guarded_branches"]))
        self.assertTrue({"search", "state", "tags", "include_pms", "guardian"}.issubset(manifest["unsupported_request_keys"]))
        candidate = (directory / "topic_query_default_results.rb").read_text()
        self.assertIn("TopicQuery.apply_custom_filters(result, self)", candidate)
        self.assertIn("DiscoursePluginRegistry.apply_modifier", candidate)
        self.assertIn("if SiteSetting.tagging_enabled", candidate)
        self.assertIn("self.class.validate_options!(@options, true)", candidate)
        self.assertIn("attr_reader :user, :guardian", candidate)
        self.assertNotIn("attr_accessor :user", candidate)

    def test_candidate_tampering_and_false_stage_promotion_are_rejected(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage2"
            shutil.copytree(HERE / "progressive/stage2", target)
            with patch.object(probe_default_results, "COMPONENT", target):
                run = probe_default_results.DefaultResultsRun()
                try:
                    run.provenance()
                    path = target / "topic_query_default_results.rb"
                    path.write_bytes(path.read_bytes().replace(b"result.visible", b"result.unscoped", 1))
                    with self.assertRaises(AssertionError):
                        run.provenance()
                    with patch.object(probe_visible_page.PortableSecurityRun, "command", side_effect=RuntimeError("runtime failed")):
                        (run.path / "native.stdout").write_text("FIDELITY_STAGE2_QUERY_ENTER\n")
                        with self.assertRaises(RuntimeError):
                            run.command("native", ["unused"])
                    # Entering a failed query is recorded, but never acceptance.
                    self.assertTrue(run.evidence["native_query_executed"])
                    for flag in ("stage_parity", "stage2_accepted", "complete_default_results_accepted", "full_query_accepted", "page_accepted"):
                        self.assertFalse(run.evidence[flag], flag)
                finally:
                    shutil.rmtree(run.path)


if __name__ == "__main__":
    unittest.main()

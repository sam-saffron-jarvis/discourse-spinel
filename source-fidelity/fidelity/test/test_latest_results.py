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
import probe_latest_results


class LatestResultsTests(unittest.TestCase):
    def test_generation_is_reproducible_and_keeps_real_settings_and_callback_calls(self):
        directory = HERE / "progressive/stage3a"
        before = {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()}
        result = subprocess.run(["ruby", HERE / "tools/generate_latest_results.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()})
        manifest = json.loads((directory / "MANIFEST.json").read_text())
        self.assertFalse(manifest["live_values_used_as_inputs"])
        self.assertFalse(manifest["full_query_accepted"])
        self.assertFalse(manifest["list_hydration_accepted"])
        self.assertFalse(manifest["page_accepted"])
        source = (HERE / "source/discourse" / manifest["source"]).read_bytes()
        for span in manifest["methods"] + manifest["guarded_source_changes"]:
            self.assertEqual(hashlib.sha256(source[span["start_byte"]:span["end_byte"]]).hexdigest(), span["text_sha256"])
        candidate = (directory / "topic_query_latest_results.rb").read_text()
        for setting in ("mute_all_categories_by_default", "default_categories_muted", "default_tags_muted", "remove_muted_tags_from_latest", "shared_drafts_category"):
            self.assertIn("SiteSetting." + setting, candidate)
        self.assertIn("filter_callback.call(:latest, result, @user, options)", candidate)
        self.assertIn("TopicQuery.results_filter_callbacks", candidate)
        self.assertNotIn("def self.results_filter_callbacks\n    []", candidate)

    def test_tampered_callback_is_rejected_before_execution(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage3a"
            shutil.copytree(HERE / "progressive/stage3a", target)
            with patch.object(probe_latest_results, "COMPONENT", target):
                run = probe_latest_results.LatestResultsRun()
                try:
                    run.provenance()
                    path = target / "topic_query_latest_results.rb"
                    path.write_bytes(path.read_bytes().replace(b"filter_callback.call(:latest, result, @user, options)", b"result", 1))
                    with self.assertRaises(AssertionError):
                        run.provenance()
                    for flag in ("latest_results_accepted", "list_hydration_accepted", "full_query_accepted", "page_accepted"):
                        self.assertFalse(run.evidence[flag], flag)
                finally:
                    shutil.rmtree(run.path)


if __name__ == "__main__":
    unittest.main()

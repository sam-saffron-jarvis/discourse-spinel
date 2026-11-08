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
import probe_list_latest


class ListLatestTests(unittest.TestCase):
    def test_generation_is_reproducible_and_keeps_source_hydration_algorithms(self):
        directory = HERE / "progressive/stage3b"
        before = {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()}
        result = subprocess.run(["ruby", HERE / "tools/generate_list_latest.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {path.name: path.read_bytes() for path in directory.iterdir() if path.is_file()})
        manifest = json.loads((directory / "MANIFEST.json").read_text())
        self.assertFalse(manifest["live_values_used_as_inputs"])
        for flag in ("full_query_accepted", "json_request_accepted", "page_accepted"):
            self.assertFalse(manifest[flag])
        for span in manifest["guarded_changes"]:
            source = (HERE / "source/discourse" / span["source"]).read_bytes()
            self.assertEqual(hashlib.sha256(source[span["start_byte"]:span["end_byte"]]).hexdigest(), span["text_sha256"])
        query = (directory / "topic_query_list_latest.rb").read_text()
        for text in ("create_list(:latest, {}, latest_results)", "prioritize_pinned_topics(topics, options)",
                "unpinned_topics.offset(offset).to_a", "TopicList.new(filter, @user, topics, options.merge(@options))"):
            self.assertIn(text, query)
        hydration = (directory / "topic_list.rb").read_text()
        for text in ("UserLookup.new(user_ids)", "GroupLookup.new(group_ids)", "ft.posters_summary(user_lookup:",
                "ft.participants_summary(user_lookup:", "ft.participant_groups_summary(group_lookup:",
                "DiscoursePluginRegistry.topic_preloader_associations.each", "Topic.preload_custom_fields(@topics, preloaded_custom_fields)",
                "TopicList.preload(@topics, self)", "ActiveRecord::Associations::Preloader.new"):
            self.assertIn(text, hydration)
        self.assertNotIn("def attributes", hydration)
        self.assertNotIn("SELECT", hydration)

    def test_tampered_hydration_is_rejected_without_promoting_request_or_page(self):
        with tempfile.TemporaryDirectory() as directory:
            target = Path(directory) / "stage3b"
            shutil.copytree(HERE / "progressive/stage3b", target)
            with patch.object(probe_list_latest, "COMPONENT", target):
                run = probe_list_latest.ListLatestRun()
                try:
                    run.provenance()
                    path = target / "topic_list.rb"
                    path.write_bytes(path.read_bytes().replace(b"ft.posters_summary(user_lookup: user_lookup)", b"[]", 1))
                    with self.assertRaises(AssertionError):
                        run.provenance()
                    for flag in ("list_hydration_accepted", "json_request_accepted", "full_query_accepted", "page_accepted"):
                        self.assertFalse(run.evidence[flag], flag)
                finally:
                    shutil.rmtree(run.path)

    def test_main_failure_exits_nonzero_and_never_marks_stage_passed(self):
        run = probe_list_latest.ListLatestRun()
        try:
            with patch.object(probe_list_latest, "ListLatestRun", return_value=run), \
                    patch.object(run, "provenance"), patch.object(run, "generate", side_effect=RuntimeError("strict compile refusal")), \
                    patch.object(run, "oracle") as oracle, patch.object(run, "run_partial") as execute:
                with self.assertRaisesRegex(RuntimeError, "strict compile refusal"):
                    probe_list_latest.main()
                oracle.assert_not_called()
                execute.assert_not_called()
                self.assertEqual(run.evidence["status"], "FAILED_progressive_stage3b")
                for flag in ("native_query_executed", "stage_parity", "list_hydration_accepted", "json_request_accepted", "full_query_accepted", "page_accepted"):
                    self.assertFalse(run.evidence[flag], flag)
        finally:
            shutil.rmtree(run.path)


if __name__ == "__main__":
    unittest.main()

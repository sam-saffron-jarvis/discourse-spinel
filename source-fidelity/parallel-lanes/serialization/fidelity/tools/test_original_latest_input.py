import tempfile
import unittest
import sys
from pathlib import Path
from types import SimpleNamespace
from unittest.mock import patch

sys.path.insert(0, str(Path(__file__).resolve().parent))
from original_latest_input import _run_probe, parse_diagnostics, parse_strict_failure

class DiagnosticInventoryTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name) / "input"
        self.source = self.root / "lib/topic_list_responder.rb"
        self.source.parent.mkdir(parents=True)
        self.source.write_text("module TopicListResponder\n  format.json { render_serialized(list, TopicListSerializer) }\nend\n")

    def tearDown(self):
        self.tmp.cleanup()

    def diag(self, path, line=2, col=3, message="`respond_to` arm `format.json` dropped"):
        return f"roundhouse: {path}:{line}:{col}: warning[lower_residue]: {message}"

    def test_strict_failure_skips_survey_hint_and_maps_unique_source_construct(self):
        controller = self.root / "app/controllers/list_controller.rb"
        controller.parent.mkdir(parents=True)
        controller.write_text("class ListController\n  skip_before_action :xhr\n  before_action :set_category,\n                only: [Discourse.filters.map { |f| f }]\n  before_action :ensure_login, except: [:index]\nend\n")
        text = ("roundhouse: hint: re-run with --survey to record unsupported constructs\n"
                f"roundhouse: ingest {self.root}: unsupported construct in {controller}: `before_action` `only:`")
        got = parse_strict_failure(text, self.root)
        self.assertEqual(got["classification"], "strict_ingest_first_failure")
        self.assertEqual(got["source"], "app/controllers/list_controller.rb")
        self.assertIn("unsupported construct in", got["text"])
        self.assertEqual(got["source_span"]["start_line"], 3)
        self.assertEqual(got["source_span"]["start_column"], 3)
        self.assertIn("inferred", got["source_location_status"])

    def test_actual_diagnostic_maps_to_locked_original_source_span(self):
        got = parse_diagnostics(self.diag(self.source.resolve()), self.root)
        self.assertEqual(got["diagnostic_categories"], {"warning[lower_residue]": 1})
        item = got["first_source_failure"]
        self.assertEqual(item["source"], "lib/topic_list_responder.rb")
        self.assertEqual(item["source_span"], {"start_byte": 28, "end_byte": 29,
                                               "start_line": 2, "start_column": 3})

    def test_no_diagnostics_does_not_keep_historical_claims(self):
        got = parse_diagnostics("", self.root)
        self.assertEqual(got["diagnostics"], [])
        self.assertIsNone(got["first_source_failure"])
        self.assertEqual(got["diagnostic_categories"], {})

    def test_changed_or_unknown_source_is_not_attributed_to_stale_file(self):
        changed = Path(self.tmp.name) / "changed.rb"
        changed.write_text("changed source\n")
        got = parse_diagnostics(self.diag(changed.resolve()), self.root)
        self.assertIsNone(got["first_source_failure"])
        self.assertIsNone(got["diagnostics"][0]["source"])

    def test_malformed_output_is_retained_but_never_claimed_as_failure(self):
        got = parse_diagnostics("roundhouse: warning[lower_residue] malformed\n", self.root)
        self.assertEqual(got["diagnostics"], [])
        self.assertEqual(got["malformed_lines"][0]["text"], "roundhouse: warning[lower_residue] malformed")
        self.assertIsNone(got["first_source_failure"])

    def test_nonzero_probe_result_and_raw_failed_output_are_preserved(self):
        with tempfile.TemporaryDirectory() as td:
            output = Path(td)
            source_root = output / "src"
            source_root.mkdir()
            binary = output / "roundhouse"
            binary.write_text("not actually executed")
            with patch("original_latest_input.subprocess.run",
                       return_value=SimpleNamespace(returncode=17, stdout="partial out", stderr="failed here\n")):
                result = _run_probe(binary, source_root, output, "strict", [])
            self.assertEqual(result["returncode"], 17)
            self.assertEqual((output / "strict.stdout").read_text(), "partial out")
            self.assertEqual((output / "strict.stderr").read_text(), "failed here\n")

if __name__ == "__main__":
    unittest.main()

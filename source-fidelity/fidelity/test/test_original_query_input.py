from pathlib import Path
import subprocess
import json
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from probe_original_query import QueryRun, audit_projection, diagnostics


class OriginalQueryInputTest(unittest.TestCase):
    def test_initializer_projection_keeps_whole_methods_and_every_byte_is_audited(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            app = Path(temp)
            subprocess.run(["ruby", str(HERE / "tools/project_query_initializer.rb"), str(HERE / "source/discourse"), str(app)], check=True)
            maps = audit_projection(app)
            query = next(item for item in maps if item["source"] == "lib/topic_query.rb")
            self.assertEqual({s["role"] for s in query["selected_spans"] if s["role"].startswith("whole_method:")},
                             {"whole_method:initialize", "whole_method:public_valid_options", "whole_method:valid_options"})
            data = (app / query["generated"]).read_text()
            self.assertIn("options.assert_valid_keys(TopicQuery.valid_options)", data)
            self.assertIn("@options = options.dup", data)
            self.assertIn("@guardian = options[:guardian] || Guardian.new(@user)", data)
            self.assertNotIn("def list_latest", data)
            self.assertNotIn("def default_results", data)
            target = app / query["generated"]
            target.write_bytes(target.read_bytes() + b"\n")
            with self.assertRaises(AssertionError):
                audit_projection(app)

    def test_legacy_support_headers_also_have_source_span_coverage(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            app = Path(temp)
            subprocess.run(["ruby", str(HERE / "tools/project_source.rb"), str(HERE / "source/discourse"), str(app)], check=True)
            maps = audit_projection(app)
            self.assertTrue(all(any(span["role"] == "owner_header" for span in item["selected_spans"]) for item in maps))

    def test_real_plugin_state_mismatch_is_not_trimmed_or_accepted(self):
        with tempfile.TemporaryDirectory() as temp:
            run = QueryRun.__new__(QueryRun)
            run.path = Path(temp)
            run.evidence = {}
            rows = {"native-page0": [{"kind": "initializer", "input_page": 0}],
                    "native-page1": [{"kind": "initializer", "input_page": 1}],
                    "native-invalid": [{"kind": "invalid_option", "error": "valid: base"}]}
            for case in ("page0", "page1", "invalid"):
                rows["compat-" + case] = rows["native-" + case]
            run.records = lambda name: rows[name]
            registration = {"filters": {"live_plugin_filter": ["plugins/example/plugin.rb", 12]}}
            (run.path / "rails-oracle.stdout").write_text("FIDELITY_QUERY_REGISTRATIONS " + json.dumps(registration) + "\n")
            oracle = rows["native-page0"] + rows["native-page1"] + [{"kind": "invalid_option", "error": "valid: base, live_plugin_filter"}]
            with self.assertRaises(AssertionError):
                run.compare_oracle(oracle)
            self.assertIn("FAIL", run.evidence["initializer_parity_scope"])
            self.assertEqual(run.evidence["initializer_parity_mismatches"][0]["index"], 2)
            self.assertEqual(run.evidence["actual_rails_query_registration_inventory"], registration)

    def test_diagnostic_order_is_not_invented_runtime_reachability(self):
        with tempfile.TemporaryDirectory() as temp:
            app = Path(temp)
            path = app / "query.rb"
            path.write_text("class Example\n  MissingA.call\n  MissingB.call\nend\n")
            text = f"roundhouse: {path}:3:3: error[unsupported]: B\nroundhouse: {path}:2:3: error[unsupported]: A\nroundhouse: error[unsupported]: unlocated native form\n"
            rows = diagnostics(text, app)
            self.assertEqual([r["source_span"]["line"] for r in rows[:2]], [3, 2])
            self.assertIsNone(rows[2]["source_span"])
            self.assertEqual(rows[0]["source_span"]["start_byte"], len(b"class Example\n  MissingA.call\n  "))
            self.assertEqual(diagnostics("roundhouse: one warning only", app), [])


if __name__ == "__main__":
    unittest.main()

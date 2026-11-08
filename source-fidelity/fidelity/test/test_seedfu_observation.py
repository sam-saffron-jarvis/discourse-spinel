"""Source-observation machinery tests, never native SeedFu/registry proof."""
import json
from pathlib import Path
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from probe_seedfu_closure import SeedFuRun, MEMBERS


class SeedFuObservationTest(unittest.TestCase):
    def measurement(self, root, successful=True, initializer=True):
        run = SeedFuRun.__new__(SeedFuRun)
        run.path = root
        run.evidence = {"source_revision": "unused-no-producer-rows"}
        run.env = {}
        run.save = lambda: None
        events = [{"event": "b_call", "method": "run", "source": ["/original/seed-fu/railtie.rb", 7]}] if initializer else []
        trace = {"successful_oracle": successful, "events": events}
        (root / "rails-oracle.stdout").write_text("FIDELITY_SEEDFU_TRACE " + json.dumps(trace) + "\n")
        return run

    def test_observed_paths_never_become_native_admission_or_inputs(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            run = self.measurement(Path(temp))
            rows = [{"same_storage": True, "paths": ["/runtime/db/fixtures", "/runtime/plugin/db/fixtures"]}]
            result = run.compare_oracle(rows)
            self.assertFalse(result["native_equal"])
            self.assertFalse(result["compat_equal"])
            report = run.evidence["actual_seedfu_source_observation"]
            self.assertTrue(report["not_native_inputs"])
            self.assertTrue(report["default_array_is_not_initialized_state"])
            self.assertEqual(report["records"], rows)

    def test_failed_or_missing_initializer_observation_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            for successful, initializer in ((False, True), (True, False)):
                run = self.measurement(Path(temp), successful=successful, initializer=initializer)
                with self.assertRaises(AssertionError):
                    run.compare_oracle([{"same_storage": True, "paths": []}])

    def test_full_declared_require_autoload_closure_includes_initializer_and_members(self):
        self.assertEqual(len(MEMBERS), 8)
        self.assertIn("lib/seed-fu/railtie.rb", MEMBERS)
        self.assertIn("lib/seed-fu/active_record_extension.rb", MEMBERS)
        self.assertIn("lib/seed-fu/runner.rb", MEMBERS)
        self.assertTrue(all(Path(name).parts[0] == "lib" and ".." not in Path(name).parts for name in MEMBERS))


if __name__ == "__main__":
    unittest.main()

import copy
import json
from pathlib import Path
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1] / "tools"))
from verify_anonymous_security import AnonymousSecurityRun, SCOPE
from verify_topic_query import TopicQueryRun, ENTRY


class AnonymousSecurityGateTest(unittest.TestCase):
    def test_broad_gate_never_opts_in_and_keeps_dynamic_dependency(self):
        run = TopicQueryRun.__new__(TopicQueryRun)
        self.assertEqual(run.emit_options(), [])
        run.path = Path("unused")
        run.evidence = {}
        with self.assertRaises(KeyError):
            run.audit_additional_inputs()
        run.validate_guardian("SiteSetting.suppress_secured_categories_from_admin")
        with self.assertRaises(AssertionError):
            run.validate_guardian("is_admin? && (raise 'unsupported construction context')")
        self.assertIn("BEGIN READ ONLY", ENTRY)
        self.assertIn("unsafe PG pool endpoint", ENTRY)

    def test_positive_gate_requires_both_no_getter_and_runtime_guard(self):
        run = AnonymousSecurityRun.__new__(AnonymousSecurityRun)
        run.validate_guardian("is_admin? && (raise 'requires a falsy predicate')")
        for invalid in ("return records if false", "is_admin?", "is_admin? && (raise 'requires a falsy predicate'); SiteSetting.suppress_secured_categories_from_admin"):
            with self.assertRaises(AssertionError):
                run.validate_guardian(invalid)

    def test_parity_requires_true_native_negative_and_zero_actual_getter_reads(self):
        with tempfile.TemporaryDirectory() as scratch:
            run = AnonymousSecurityRun.__new__(AnonymousSecurityRun)
            run.path = Path(scratch)
            run.evidence = {}
            correct = [{"kind": "row", "id": 1, "visible": True}, {"kind": "fixture", "id": 101}]
            observations = {"native": correct, "compat": copy.deepcopy(correct), "native-wrong-scope": correct + [{"kind": "fixture", "id": 111}]}
            run.records = lambda name: observations[name]
            trace = {"setting_getter_calls": 0, "successful_probe": True, "counts": {"filter_allowed_categories": 4, "is_admin?": 6}}
            def save_trace():
                (run.path / "rails-oracle.stdout").write_text("FIDELITY_ANONYMOUS_REACHABILITY " + json.dumps(trace) + "\n")
            save_trace()
            result = run.compare_oracle(correct)
            self.assertTrue(result["native_equal"] and result["compat_equal"])
            self.assertEqual(result["scope"], SCOPE)
            trace["setting_getter_calls"] = 1
            save_trace()
            with self.assertRaises(AssertionError):
                run.compare_oracle(correct)
            trace["setting_getter_calls"] = 0
            trace["successful_probe"] = False
            save_trace()
            with self.assertRaises(AssertionError):
                run.compare_oracle(correct)
            trace["successful_probe"] = True
            save_trace()
            observations["native-wrong-scope"] = correct
            with self.assertRaises(AssertionError):
                run.compare_oracle(correct)
            observations["native-wrong-scope"] = correct + [{"kind": "fixture", "id": 111}]
            observations["native"] = copy.deepcopy(correct)
            observations["native"][0]["visible"] = 1
            with self.assertRaises(AssertionError):
                run.compare_oracle(correct)


if __name__ == "__main__":
    unittest.main()

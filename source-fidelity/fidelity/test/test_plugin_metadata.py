"""Metadata prefix comparator controls, not plugin activation evidence."""
from pathlib import Path
import copy
import sys
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from verify_plugin_metadata import MetadataRun


class PluginMetadataTest(unittest.TestCase):
    def test_metadata_comparison_preserves_values_types_and_scope(self):
        run = MetadataRun.__new__(MetadataRun)
        rows = [{"kind": "plugin_metadata", "name": "test-source-data", "version": "0.1",
                 "meta_topic_id": 7, "official": True}]
        run.records = lambda _: rows
        result = run.compare_oracle(copy.deepcopy(rows))
        self.assertTrue(result["native_equal"])
        self.assertIn("no native script activation", result["scope"])
        for key, value in (("name", "changed"), ("meta_topic_id", "7"), ("official", 1)):
            wrong = copy.deepcopy(rows)
            wrong[0][key] = value
            with self.assertRaises(AssertionError):
                run.compare_oracle(wrong)
        with self.assertRaises(AssertionError):
            run.compare_oracle([])


if __name__ == "__main__":
    unittest.main()

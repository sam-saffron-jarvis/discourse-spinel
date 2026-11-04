"""Unit tests for evidence machinery, not substitutes for live runtime proof."""
import importlib.util
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(ROOT / "tools"))
spec = importlib.util.spec_from_file_location("verify", ROOT / "tools/verify.py")
verify = importlib.util.module_from_spec(spec)
spec.loader.exec_module(verify)


class EvidenceToolsTest(unittest.TestCase):
    def test_comparator_rejects_type_and_scope_differences(self):
        rows = [{"id": 7, "visible": True, "category_id": None}]
        verify.equal_records(rows, [{"category_id": None, "visible": True, "id": 7}])
        for wrong in (
            [{"id": 7, "visible": 1, "category_id": None}],
            [{"id": 7, "visible": True, "category_id": 0}],
            [{"id": 8, "visible": True, "category_id": None}],
            [],
        ):
            with self.assertRaisesRegex(AssertionError, "scope/query/type"):
                verify.equal_records(rows, wrong)

    def test_projection_copies_selected_ast_nodes_at_original_offsets(self):
        build = ROOT / "build"
        build.mkdir(exist_ok=True)
        with tempfile.TemporaryDirectory(prefix="projection-unit-", dir=build) as temp:
            for script in ("project_source.rb", "project_topic_query.rb"):
                target = Path(temp) / script.removesuffix(".rb")
                subprocess.run(["ruby", str(ROOT / "tools" / script), str(ROOT / "source/discourse"), str(target)], check=True)
                maps = json.loads((target / "projection-map.json").read_text())
                for item in maps:
                    original = (ROOT / "source/discourse" / item["source"]).read_bytes()
                    generated = (target / item["generated"]).read_bytes()
                    self.assertEqual(len(original), len(generated))
                    self.assertEqual(original.count(b"\n"), generated.count(b"\n"))
                    for span in item["selected_spans"]:
                        start, end = span["start_byte"], span["end_byte"]
                        self.assertEqual(original[start:end], generated[start:end])
                        self.assertEqual(verify.digest(original[start:end]), span["text_sha256"])
                if script == "project_topic_query.rb":
                    expression = (target / "topic-query-expression.rb").read_text()
                    self.assertIn('@guardian.filter_allowed_categories(', expression)
                    self.assertIn('category_id_column: "categories.id"', expression)
                    self.assertIn('result = result.merge(all_listable_topics)', expression)
                    self.assertNotIn('options.reverse_merge!', expression)
                    self.assertNotIn('def default_results', expression)
                    self.assertIn('SiteSetting.suppress_secured_categories_from_admin', (target / "app/models/topic_guardian.rb").read_text())
                    self.assertNotIn('def self.suppress_secured_categories_from_admin', (target / "app/models/site_setting.rb").read_text())
            topic = (Path(temp) / "project_source/app/models/topic.rb").read_text()
            self.assertIn("scope :listable_topics, -> { where.not(topics: { archetype: Archetype.private_message }) }", topic)
            self.assertNotIn("def trash!", topic)
            self.assertNotIn("def self.max_fancy_title_length", topic)


if __name__ == "__main__":
    unittest.main()

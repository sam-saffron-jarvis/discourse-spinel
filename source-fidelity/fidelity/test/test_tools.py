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

    def test_activation_projection_preserves_whole_producers_and_labels_partial_eval(self):
        from probe_original_query import audit_projection
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temp:
            for mode in (None, "--eval-prefix"):
                target = Path(temp) / (mode or "whole")
                args = ["ruby", str(ROOT / "tools/project_plugin_activation.rb"), str(ROOT / "source/discourse"), str(target)]
                if mode:
                    args.append(mode)
                subprocess.run(args, check=True)
                maps = audit_projection(target)
                item = next(m for m in maps if m["source"] == "lib/plugin/instance.rb")
                roles = [span["role"] for span in item["selected_spans"]]
                text = (target / item["generated"]).read_text()
                self.assertIn("original_memo_reader_loop", roles)
                self.assertIn("instance_eval File.read(path), path", text)
                self.assertIn("class_eval %Q{", text)
                if mode:
                    self.assertIn("original_evaluation_statement_ONLY", roles)
                    self.assertNotIn("whole_method:activate!", roles)
                    self.assertNotIn("write_extra_js!", text)
                else:
                    self.assertIn("whole_method:activate!", roles)
                    self.assertIn("whole_method:notify_after_initialize", roles)
                    self.assertIn("whole_method:reloadable_patch", roles)
                    self.assertIn("write_extra_js!", text)
                    self.assertIn("ensure_images_symlink!", text)
                    self.assertNotIn("PARTIAL_activate_header", roles)

    def test_metadata_prefix_retains_real_parser_and_original_argument_producer(self):
        with tempfile.TemporaryDirectory(dir=ROOT / "build") as temp:
            app = Path(temp)
            subprocess.run(["ruby", str(ROOT / "tools/project_plugin_activation.rb"), str(ROOT / "source/discourse"), str(app), "--metadata-prefix"], check=True)
            from probe_original_query import audit_projection
            maps = audit_projection(app)
            instance = next(item for item in maps if item["source"] == "lib/plugin/instance.rb")
            roles = [span["role"] for span in instance["selected_spans"]]
            self.assertIn("whole_method:parse_from_source", roles)
            self.assertNotIn("whole_method:activate!", roles)
            for source, generated in (("lib/plugin/metadata.rb", "app/models/plugin/metadata.rb"), ("config/official_plugins.json", "config/official_plugins.json")):
                self.assertEqual((ROOT / "source/discourse" / source).read_bytes(), (app / generated).read_bytes())
            text = (app / instance["generated"]).read_text()
            self.assertIn("metadata = Plugin::Metadata.parse(source)", text)
            self.assertIn("new(metadata, path)", text)
            self.assertNotIn("def activate!", text)

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

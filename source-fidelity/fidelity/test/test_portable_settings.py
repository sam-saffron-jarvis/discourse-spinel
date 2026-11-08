import hashlib
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from verify import equal_records


class PortableSettingsTests(unittest.TestCase):
    def test_manifest_is_separate_and_source_derived_not_an_effective_snapshot(self):
        manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
        self.assertEqual(manifest["profile"], "patched-core-no-plugins-shared-settings")
        self.assertEqual(manifest["baseline_revision"], "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8")
        self.assertFalse(manifest["observed_values_or_effective_snapshot_as_inputs"])
        self.assertFalse(manifest["full_site_setting_api_accepted"])
        self.assertFalse(manifest["core_latest_accepted"])
        self.assertEqual(manifest["generated_definitions"], 1111)
        for name, expected in manifest["candidate_source_sha256"].items():
            self.assertEqual(hashlib.sha256((HERE / "compat" / name).read_bytes()).hexdigest(), expected, name)
        for name, expected in manifest["reference_source_sha256"].items():
            self.assertEqual(hashlib.sha256((HERE.parent / "discourse" / name).read_bytes()).hexdigest(), expected, name)

        generated = manifest["generated_test_consumer"]
        self.assertFalse(generated["production_input"])
        self.assertEqual(hashlib.sha256((HERE / generated["path"]).read_bytes()).hexdigest(), generated["sha256"])
        for name, fixture in manifest["unit_only_fixtures"].items():
            self.assertFalse(fixture["production_input"])
            self.assertEqual(hashlib.sha256((HERE / name).read_bytes()).hexdigest(), fixture["generated_sha256"])
            source = (HERE.parent / "discourse" / fixture["source"]).read_bytes()
            selected = source[fixture["start_byte"]:fixture["end_byte"]]
            self.assertEqual(hashlib.sha256(selected).hexdigest(), fixture["selected_text_sha256"])
            self.assertIn(selected, (HERE / name).read_bytes())

    def test_declaration_generation_is_reproducible(self):
        paths = [path for directory in (HERE / "compat", HERE / "test/generated") for path in directory.rglob("*") if path.is_file()]
        before = {str(path): path.read_bytes() for path in paths}
        result = subprocess.run(["ruby", HERE / "tools/generate_portable_settings.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {str(path): path.read_bytes() for directory in (HERE / "compat", HERE / "test/generated")
                                  for path in directory.rglob("*") if path.is_file()})

    def test_shared_unit_store_contract(self):
        result = subprocess.run(["ruby", HERE / "test/portable_settings_store_probe.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        proof = json.loads(result.stdout)
        self.assertEqual(proof["definitions"], 1111)
        self.assertFalse(proof["full_site_setting_accepted"])
        self.assertFalse(proof["core_latest_accepted"])

    def test_source_configuration_precedence_and_unsupported_erb(self):
        with tempfile.TemporaryDirectory(prefix="portable-config-unit-", dir=HERE / "build") as directory:
            env = dict(os.environ, PORTABLE_CONFIGURATION_TEST_DIR=directory)
            result = subprocess.run(["ruby", HERE / "test/portable_settings_configuration_probe.rb"], env=env,
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertFalse(json.loads(result.stdout)["erb_admitted"])

    def test_candidate_model_preserves_all_original_helpers_and_callbacks(self):
        original = (HERE.parent / "discourse/app/models/site_setting.rb").read_text()
        expected = original.replace("class SiteSetting < ActiveRecord::Base",
            'require_relative "../../lib/site_settings/portable_rails_extension"\n\nclass SiteSetting < ActiveRecord::Base', 1)
        expected = expected.replace("  extend SiteSettingExtension",
            "  extend SiteSettingExtension\n  extend SiteSettings::PortableSettingsContext\n  extend SiteSettings::PortableRailsExtension\n  extend SiteSettings::PortableScalarReaders", 1)
        self.assertEqual(expected, (HERE / "compat/discourse/app/models/site_setting.rb").read_text())

    def test_production_scalar_accessor_module_and_reversible_group_map_unit(self):
        result = subprocess.run(["ruby", HERE / "test/portable_scalar_accessors_probe.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        proof = json.loads(result.stdout)
        self.assertEqual(proof["old_map"], [0, 5, 0, 1])
        self.assertEqual(proof["new_map"], [5, 1])
        self.assertFalse(proof["native_upcoming_changes_accepted"])
        self.assertFalse(proof["core_latest_accepted"])

    def test_latest_projection_preserves_whole_method_bodies_and_option_branches(self):
        from probe_original_query import audit_projection
        with tempfile.TemporaryDirectory(prefix="latest-method-unit-", dir=HERE / "build") as directory:
            result = subprocess.run(["ruby", HERE / "tools/project_core_latest.rb", HERE / "source/discourse", directory],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            maps = audit_projection(Path(directory))
            query = next(item for item in maps if item["generated"] == "app/models/topic_query.rb")
            methods = {span["role"] for span in query["selected_spans"]}
            self.assertIn("whole_method:default_results", methods)
            self.assertIn("whole_method:latest_results", methods)
            self.assertIn("whole_method:list_latest", methods)
            self.assertIn("source_visibility:protected", methods)
            closure = json.loads((Path(directory) / "latest-method-closure.json").read_text())
            self.assertFalse(closure["source_values_or_runtime_reachability_used"])
            self.assertFalse(closure["core_latest_accepted"])
            self.assertEqual(closure["method_count"], 20)

    def test_latest_helper_inputs_are_complete_originals_not_empty_interfaces(self):
        from latest_dependencies import materialize
        from probe_original_query import audit_projection
        with tempfile.TemporaryDirectory(prefix="latest-helper-unit-", dir=HERE / "build") as directory:
            result = subprocess.run(["ruby", HERE / "tools/project_core_latest.rb", HERE / "source/discourse", directory],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            materialize(Path(directory))
            maps = audit_projection(Path(directory))
            concern = next(item for item in maps if item["generated"] == "app/models/active_model_serialization.rb")
            self.assertEqual(concern["source_root"], "framework")
            self.assertEqual(concern["source_sha256"], concern["generated_sha256"])
            self.assertIn(b"def serializable_hash", (Path(directory) / concern["generated"]).read_bytes())
            poster = next(item for item in maps if item["generated"] == "app/models/topic_poster.rb")
            self.assertEqual(poster["source_sha256"], poster["generated_sha256"])
            self.assertIn(b"class TopicPoster < OpenStruct", (Path(directory) / poster["generated"]).read_bytes())

    def test_fixed_flag_delegates_expand_only_the_original_source_macro(self):
        manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
        transform = next(item for item in manifest["source_transforms"] if item["source"] == "app/models/post_action_type.rb")
        baseline = (HERE.parent / "discourse" / transform["source"]).read_bytes()
        candidate = (HERE / "compat/discourse" / transform["source"]).read_bytes()
        start, end = transform["replaced_start_byte"], transform["replaced_end_byte"]
        self.assertEqual(hashlib.sha256(baseline[start:end]).hexdigest(), transform["original_text_sha256"])
        replacement = "\n\n    ".join(f"def {name}(*args)\n      PostActionTypeView.new.{name}(*args)\n    end"
                                         for name in transform["delegated_names"]).encode()
        self.assertEqual(candidate, baseline[:start] + replacement + baseline[end:])
        self.assertIn("types", transform["delegated_names"])
        self.assertIn("is_flag?", transform["delegated_names"])

    def test_candidate_read_model_projections_have_a_separate_mutation_rejecting_audit(self):
        from latest_dependencies import materialize
        from compat_source_audit import audit
        from probe_original_query import audit_projection
        with tempfile.TemporaryDirectory(prefix="candidate-model-unit-", dir=HERE / "build") as directory:
            app = Path(directory)
            result = subprocess.run(["ruby", HERE / "tools/project_core_latest.rb", HERE / "source/discourse", app],
                                    capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            materialize(app, read_models=True)
            result = subprocess.run(["ruby", HERE / "tools/project_latest_models.rb", HERE / "source/discourse", app,
                                     HERE / "compat/discourse"], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            originals = audit_projection(app)
            candidates = audit(app)
            expected = {"app/models/post_action_type.rb", "app/models/post_action.rb", "app/models/category_user.rb", "app/models/topic_user.rb",
                        "app/models/dismissed_topic_user.rb"}
            self.assertEqual({item["source"] for item in candidates}, expected)
            self.assertFalse(expected & {item["source"] for item in originals})
            selected = next(item for item in candidates if item["source"] == "app/models/post_action_type.rb")
            target = app / selected["generated"]
            target.write_bytes(target.read_bytes().replace(b"PostActionTypeView", b"WrongActionTypeXx", 1))
            with self.assertRaises(AssertionError):
                audit(app)

    def test_new_security_profile_keeps_the_original_setting_dependency(self):
        from probe_portable_security import PortableSecurityRun
        run = PortableSecurityRun.__new__(PortableSecurityRun)
        self.assertEqual(run.emit_options(), [])
        run.validate_guardian("SiteSetting.suppress_secured_categories_from_admin")
        with self.assertRaises(AssertionError):
            run.validate_guardian("is_admin? && false")
        with self.assertRaises(AssertionError):
            run.validate_guardian("SiteSetting.suppress_secured_categories_from_admin; requires a falsy predicate")

    def test_historical_oracle_root_remains_the_original_checkout(self):
        from verify import Run, ROOT
        from probe_portable_rails import HybridRailsRun
        self.assertEqual(Run.__new__(Run).oracle_application_root(), ROOT / "discourse")
        hybrid = HybridRailsRun.__new__(HybridRailsRun)
        self.assertEqual(hybrid.oracle_application_root(), ROOT / "discourse")
        hybrid.candidate_root = HERE / "build/unit-only-candidate-root"
        self.assertEqual(hybrid.oracle_application_root(), hybrid.candidate_root)

    def test_comparison_rejects_false_zero_and_changed_runtime_type(self):
        for wrong in (0, "false", None):
            with self.assertRaises(AssertionError):
                equal_records([["flag", "FalseClass", False]], [["flag", "FalseClass", wrong]])
        with self.assertRaises(AssertionError):
            equal_records([["limit", "Integer", 1]], [["limit", "Float", 1.0]])


if __name__ == "__main__":
    unittest.main()

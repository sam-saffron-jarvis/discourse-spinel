from pathlib import Path
import copy
import json
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from probe_core_no_plugins import CoreNoPluginsRun
from core_getter_input import CODE, BOOT
from core_provider_input import materialize as provider_dependencies
from core_source_inventory import acquire


class CoreNoPluginsTest(unittest.TestCase):
    def output(self, directory, **profile_changes):
        profile = {"load_plugins_env": "0", "load_plugins": False,
                   "plugin_instance_names": [], "compiled_plugin_sources": [], "loaded_plugin_sources": [],
                   "original_configuration": {"config/application.rb": "source-hash"}}
        profile.update(profile_changes)
        lines = [("FIDELITY_CORE_NO_PLUGINS ", profile),
                 ("FIDELITY_CORE_REFERENCE ", {"row_count": 1, "scope": "reference only"}),
                 ("FIDELITY_QUERY_REGISTRATIONS ", {"valid_options": ["core"], "filters": {}})]
        (directory / "rails-oracle.stdout").write_text("\n".join(prefix + json.dumps(value) for prefix, value in lines))

    def run_object(self, directory):
        run = CoreNoPluginsRun.__new__(CoreNoPluginsRun)
        run.path = directory
        run.trace_activation = False
        run.reference_only = True
        run.env = {}
        run.evidence = {"source_hashes": {"config/application.rb": "source-hash"}}
        return run

    def test_loaded_official_or_other_plugins_fail_closed(self):
        for change in ({"load_plugins_env": "1"}, {"load_plugins": True},
                       {"plugin_instance_names": ["discourse-official-plugin"]},
                       {"loaded_plugin_sources": ["plugins/discourse-official/plugin.rb"]},
                       {"compiled_plugin_sources": ["plugins/discourse-other/register_provider.rb"]}):
            with tempfile.TemporaryDirectory() as temp:
                path = Path(temp)
                self.output(path, **change)
                with self.assertRaises(AssertionError):
                    self.run_object(path).compare_oracle([{"kind": "initializer"}])

    def test_reference_is_not_claimed_as_native_page_acceptance(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            self.output(path)
            run = self.run_object(path)
            result = run.compare_oracle([{"kind": "initializer"}])
            self.assertTrue(result["reference_only"])
            self.assertFalse(result["native_equal"])
            self.assertFalse(result["core_page_accepted"])

    def test_constructor_still_compares_complete_error_text(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp)
            self.output(path)
            run = self.run_object(path)
            run.reference_only = False
            rows = {"native-page0": [{"kind": "initializer", "input_page": 0}],
                    "native-page1": [{"kind": "initializer", "input_page": 1}],
                    "native-invalid": [{"kind": "invalid_option", "error": "valid: full core keys"}]}
            for case in ("page0", "page1", "invalid"):
                rows["compat-" + case] = rows["native-" + case]
            run.records = lambda name: rows[name]
            oracle = rows["native-page0"] + rows["native-page1"] + [{"kind": "invalid_option", "error": "valid: different core keys"}]
            with self.assertRaises(AssertionError):
                run.compare_oracle(oracle)
            self.assertIn("initializer_parity_mismatches", run.evidence)

    def test_core_getter_input_keeps_original_boot_and_no_activation_sources(self):
        self.assertIn("config/initializers/005-site_settings.rb", BOOT)
        self.assertIn("app/models/site_setting.rb", CODE)
        self.assertIn("lib/site_setting_extension.rb", CODE)
        self.assertNotIn("lib/plugin/instance.rb", CODE)
        self.assertFalse(any(path.startswith("plugins/") for path in CODE))

    def test_provider_dependencies_keep_original_boot_and_verified_source_members(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as temp:
            app = Path(temp)
            report = provider_dependencies(app)
            self.assertFalse(report["plugin_sources_included"])
            self.assertFalse(report["railtie_body_replaced"])
            self.assertFalse(report["observed_values_or_sql_used_as_inputs"])
            self.assertEqual({group["gem"] for group in report["complete_original_gem_sources"]}, {"mini_sql", "rails_multisite"})
            for item in report["complete_original_core_files"]:
                self.assertEqual((app / item["generated"]).read_bytes(), (HERE / "source/discourse" / item["path"]).read_bytes())
            for group in report["complete_original_gem_sources"]:
                for item in group["files"]:
                    staged = app / "vendor/bundle/ruby/4.0.0/gems" / f'{group["gem"]}-{group["version"]}' / item["package_member"]
                    self.assertEqual(staged.read_bytes(), (HERE / item["path"]).read_bytes())
            self.assertEqual((app / "Gemfile.lock").read_bytes(), (HERE.parent / "discourse/Gemfile.lock").read_bytes())
            initializer = (app / "config/initializers/000-mini_sql.rb").read_text()
            self.assertIn("::DB = MiniSqlMultisiteConnection.instance", initializer)
            self.assertIn("compile-only", report["scope"])

    def test_provider_trace_rejects_fabricated_types_fields_order_or_source(self):
        events = [
            {"event": "call", "method": "all", "source": ["/original/lib/site_settings/db_provider.rb", 13]},
            {"event": "call", "method": "new_row_materializer", "source": ["/original/mini_sql/postgres/deserializer_cache.rb", 58]},
            {"event": "line", "method": "new_row_materializer", "source": ["/original/mini_sql/postgres/deserializer_cache.rb", 74], "anonymous_row_class": True, "observed_row_fields": ["name", "data_type", "value"]},
            {"event": "c_call", "method": "type_map=", "source": ["/original/mini_sql/postgres/connection.rb", 136]},
            {"event": "c_return", "method": "getvalue", "source": ["(original evaluated method)", 3], "result_class": "Integer"},
            {"event": "c_return", "method": "getvalue", "source": ["(original evaluated method)", 3], "result_class": "String"},
        ]
        for index, event in enumerate(events):
            event["order"] = index + 1
        original = {"successful_oracle": True, "events": events, "loaded_provider_source_hashes": {"/not-a-verified-package": "fake"}}
        variants = [copy.deepcopy(original) for _ in range(5)]
        variants[0]["successful_oracle"] = False
        variants[1]["events"][0]["order"] = 2
        variants[2]["events"][2]["observed_row_fields"] = ["name", "value"]
        variants[3]["events"][4]["result_class"] = "String"
        # The unchanged final variant reaches and fails exact loaded-byte proof.
        for trace in variants:
            with tempfile.TemporaryDirectory() as temp:
                directory = Path(temp)
                self.output(directory)
                with (directory / "rails-oracle.stdout").open("a") as file:
                    file.write("\nFIDELITY_CORE_PROVIDER_TRACE " + json.dumps(trace))
                run = self.run_object(directory)
                run.provider_dependencies = True
                run.evidence["framework_sources"] = []
                with self.assertRaises(AssertionError):
                    run.compare_oracle([{"kind": "initializer"}])

    def test_provider_flag_cannot_bypass_getter_compile_only_scope(self):
        result = subprocess.run([sys.executable, str(HERE / "tools/probe_core_no_plugins.py"), "--provider-dependencies"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 2)
        self.assertIn("requires --getter-input", result.stderr)

    def test_plugin_source_inventory_refuses_before_acquisition(self):
        with tempfile.TemporaryDirectory() as temp:
            path = Path(temp) / "evidence.json"
            profile = {"load_plugins_env": "0", "load_plugins": False, "plugin_instance_names": [],
                       "compiled_plugin_sources": [], "loaded_plugin_sources": []}
            path.write_text(json.dumps({"actual_no_plugin_boot": profile,
                "original_core_query_reference": {"original_core_calls": [{"source": "plugins/official/plugin.rb"}]}}))
            with self.assertRaises(AssertionError):
                acquire(path)


if __name__ == "__main__":
    unittest.main()

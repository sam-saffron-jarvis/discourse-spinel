import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
import probe_serialized_latest
from serialization_source_audit import audit


class SerializedLatestTests(unittest.TestCase):
    def test_all_source_generators_are_reproducible_and_separately_audited(self):
        paths = [HERE / "SOURCE_LOCK.json", HERE / "compat/MANIFEST.json"]
        paths += [p for folder in ("compat/discourse", "progressive/stage4") for p in (HERE / folder).rglob("*") if p.is_file()]
        before = {str(p): p.read_bytes() for p in paths}
        for name in ("generate_portable_serializers.rb", "generate_serializer_declarations.rb",
                     "generate_serializer_read_dependencies.rb", "generate_portable_settings.rb"):
            result = subprocess.run(["ruby", HERE / "tools" / name], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {str(p): p.read_bytes() for p in paths})
        reports = audit()
        self.assertEqual(len(reports), 3)
        declaration = reports["progressive/stage4/SERIALIZER_DECLARATIONS_MANIFEST.json"]
        self.assertFalse(declaration["captured_payload_as_input"])
        self.assertFalse(declaration["live_settings_as_inputs"])
        serializer = (HERE / "compat/discourse/app/serializers/application_serializer.rb").read_text()
        self.assertIn("def _root_embed; true; end", serializer)
        listable = (HERE / "compat/discourse/app/serializers/listable_topic_serializer.rb").read_text()
        self.assertIn("alias include_new_posts? has_user_data", listable)
        self.assertNotIn("def include_new_posts?; true; end", listable)
        self.assertIn("merge_association", (HERE / "compat/discourse/lib/portable_serializer_read.rb").read_text())

    def test_tampered_manifest_source_or_original_method_span_is_rejected(self):
        with tempfile.TemporaryDirectory(dir=HERE / "build") as directory:
            target = Path(directory) / "fidelity"
            for folder in ("compat", "source", "progressive/stage4"):
                shutil.copytree(HERE / folder, target / folder)
            audit(target)
            for relative in ("progressive/stage4/SERIALIZER_DECLARATIONS_MANIFEST.json",
                             "compat/discourse/app/serializers/topic_list_serializer.rb",
                             "source/discourse/app/models/user.rb",
                             "source/framework/addressable-2.9.0/lib/addressable/uri.rb"):
                path = target / relative
                saved = path.read_bytes()
                path.write_bytes(saved + b"\n# tampered\n")
                with self.assertRaises(AssertionError):
                    audit(target)
                path.write_bytes(saved)

    def test_real_upload_id_and_source_configuration_encoding_units(self):
        result = subprocess.run(["ruby", HERE / "test/portable_upload_id_probe.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        with tempfile.TemporaryDirectory(dir=HERE / "build") as directory:
            env = dict(os.environ, BUNDLE_GEMFILE=str(HERE.parent / "discourse/Gemfile"),
                       PORTABLE_SERIALIZER_TEST_DIR=directory)
            result = subprocess.run(["bundle", "exec", "ruby", HERE / "test/serialization_read_support_probe.rb"],
                                    cwd=HERE.parent / "discourse", env=env, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertIn("UNIT ONLY", result.stdout)

    def test_actual_fresh_codepoint_map_runs_natively_and_on_cruby(self):
        source = (HERE / "compat/discourse/app/models/emoji.rb").read_text()
        method = re.search(r"  def self.replacement_code\(code\)\n.*?\n  end", source, re.S).group(0)
        with tempfile.TemporaryDirectory(dir=HERE / "build") as directory:
            path = Path(directory) / "codepoints.rb"
            binary = path.with_suffix("")
            path.write_text("class Emoji\n" + method + "\nend\n" +
                            'raise unless Emoji.replacement_code("1f44b-1f3fb").codepoints == [0x1f44b, 0x1f3fb]\n')
            result = subprocess.run([HERE.parent / "spinel/spinel", path, "-o", binary], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            self.assertEqual(binary.read_bytes()[:4], b"\x7fELF")
            for argv in ([binary], ["ruby", path]):
                result = subprocess.run(argv, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)

    def test_failure_never_promotes_serializer_or_request_acceptance(self):
        run = probe_serialized_latest.SerializedLatestRun()
        try:
            with patch.object(probe_serialized_latest, "SerializedLatestRun", return_value=run), \
                    patch.object(run, "provenance"), patch.object(run, "generate"), patch.object(run, "oracle"), \
                    patch.object(run, "run_partial", side_effect=RuntimeError("native serialization refusal")):
                with self.assertRaisesRegex(RuntimeError, "native serialization refusal"):
                    probe_serialized_latest.main()
                self.assertEqual(run.evidence["status"], "FAILED_full_serialized_list_experiment")
                for flag in ("native_query_executed", "stage_parity", "full_serialized_list_accepted",
                             "json_request_accepted", "full_query_accepted", "page_accepted"):
                    self.assertFalse(run.evidence[flag], flag)
        finally:
            shutil.rmtree(run.path)


if __name__ == "__main__":
    unittest.main()

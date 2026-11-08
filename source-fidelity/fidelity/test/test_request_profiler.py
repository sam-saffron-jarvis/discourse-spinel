import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
sys.path.insert(0, str(HERE / "tools"))
from oracle_sandbox import ValkeySandbox
from verify import digest


class RequestProfilerTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT, env=None):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, env=env, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_record_generation_is_reproducible_and_audited(self):
        manifest_path = HERE / "progressive/stage4_request/PROFILER_SOURCE_MANIFEST.json"
        before = manifest_path.read_bytes()
        manifest = json.loads(before)
        candidate = HERE / manifest["candidate"]
        source = candidate.read_bytes()
        self.command(["ruby", HERE / "tools/generate_request_profiler.rb"])
        self.assertEqual(manifest_path.read_bytes(), before)
        self.assertEqual(candidate.read_bytes(), source)
        self.assertEqual(digest(source), manifest["candidate_sha256"])
        for path, sha in manifest["source_sha256"].items():
            self.assertEqual(digest((HERE / "source/framework" / path).read_bytes()), sha)
        for path, sha in manifest["shared_components_sha256"].items():
            self.assertEqual(digest((HERE / path).read_bytes()), sha)
        for path, sha in manifest["application_source_sha256"].items():
            self.assertEqual(digest((HERE / "source/discourse" / path).read_bytes()), sha)
        for part in manifest["selected_spans"]:
            original = (HERE / "source/framework" / part["source"]).read_bytes()
            self.assertEqual(digest(original[part["start_byte"]:part["end_byte"]]), part["text_sha256"])
        host = manifest["host_authorization"]
        self.assertEqual(digest((HERE / host["candidate"]).read_bytes()), host["candidate_sha256"])
        for path, sha in host["application_source_sha256"].items():
            self.assertEqual(digest((ROOT / "discourse" / path).read_bytes()), sha)
        for path, sha in host["auxiliary_source_sha256"].items():
            self.assertEqual(digest((ROOT / path).read_bytes()), sha)
        for name, sha in manifest["query_cache_lifecycle"]["runtime_sha256"].items():
            self.assertEqual(digest((ROOT / name).read_bytes()), sha)
        self.assertFalse(manifest["query_cache_lifecycle"]["all_executor_hooks_accepted"])
        self.assertFalse(manifest["query_cache_lifecycle"]["observed_cache_contents_as_inputs"])
        profile = manifest["json_profile_middleware"]
        self.assertEqual(digest((HERE / profile["candidate"]).read_bytes()), profile["candidate_sha256"])
        self.assertFalse(profile["full_optional_features_accepted"])
        self.assertFalse(profile["whole_stack_accepted"])
        for name, sha in profile["application_source_sha256"].items():
            self.assertEqual(digest((HERE / "source/discourse" / name).read_bytes()), sha)
        for part in profile["selected_spans"]:
            base = HERE / ("source/framework" if part["source"].startswith("rack-") else "source/discourse")
            original = (base / part["source"]).read_bytes()
            self.assertEqual(digest(original[part["start_byte"]:part["end_byte"]]), part["text_sha256"])
        remote = manifest["remote_ip"]
        self.assertEqual(digest((HERE / remote["candidate"]).read_bytes()), remote["candidate_sha256"])
        self.assertFalse(remote["forwarded_profile_accepted"])
        self.assertFalse(remote["observed_ip_values_as_inputs"])
        self.assertFalse(remote["full_stack_accepted"])
        self.assertFalse(host["full_stack_accepted"])
        self.assertFalse(host["captured_permissions_or_runtime_hosts"])
        for path, sha in manifest["request_id_framework_binding"]["implementations_sha256"].items():
            self.assertEqual(digest((ROOT / path).read_bytes()), sha)
        self.assertFalse(manifest["request_id_framework_binding"]["full_stack_accepted"])
        response = manifest["response_middleware"]
        self.assertEqual(digest((HERE / response["candidate"]).read_bytes()), response["candidate_sha256"])
        for path, sha in response["source_sha256"].items():
            self.assertEqual(digest((ROOT / "discourse" / path).read_bytes()), sha)
        for part in response["selected_spans"]:
            original = (ROOT / "discourse" / part["source"]).read_bytes()
            self.assertEqual(digest(original[part["start_byte"]:part["end_byte"]]), part["text_sha256"])
        self.assertEqual(digest((HERE / response["request_id_candidate"]).read_bytes()), response["request_id_candidate_sha256"])
        for path, sha in response["framework_source_sha256"].items():
            self.assertEqual(digest((HERE / "source/framework" / path).read_bytes()), sha)
        self.assertEqual(digest((HERE / response["cors_candidate"]).read_bytes()), response["cors_candidate_sha256"])
        self.assertFalse(response["full_stack_accepted"])
        self.assertFalse(response["observed_payloads_as_inputs"])
        self.assertFalse(manifest["captured_values_as_inputs"])
        self.assertFalse(manifest["native_request_accepted"])

    def test_native_original_records_store_real_binary_effects_on_separate_owned_fixtures(self):
        build = Path(tempfile.mkdtemp(prefix="profiler5-runtime-", dir=HERE / "build"))
        core_binary = build / "core-probe"
        self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", HERE / "test/request_profiler_core.rb", "-o", core_binary])
        self.assertEqual(self.command([core_binary]), self.command(["ruby", HERE / "test/request_profiler_core.rb"]))
        binary = build / "store-probe"
        self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", HERE / "test/request_profiler_store.rb", "-o", binary])
        results = []
        for runtime in ("native", "cruby"):
            sandbox = ValkeySandbox(build / (runtime + "-fixture"))
            with sandbox:
                env = {**os.environ, **sandbox.environment, "FIDELITY_CACHE_OWNER_PID": str(os.getpid()),
                       "FIDELITY_CACHE_MARSHAL_DUMP": str(build / (runtime + ".marshal"))}
                argv = [binary] if runtime == "native" else ["ruby", HERE / "test/request_profiler_store.rb"]
                trace = build / (runtime + ".trace")
                output = self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, *argv], env=env)
                (build / (runtime + ".stdout")).write_bytes(output)
                self.assertIn(b"PASS actual profiler5 Marshal SETEX/load/unviewed/TTL", output)
                effects = [json.loads(line.split(b" ", 1)[1]) for line in output.splitlines() if line.startswith(b"FIDELITY_CACHE_EFFECT ")]
                self.assertEqual([row["command"] for row in effects], ["SETEX", "ZADD", "EXPIRE", "ZREMRANGEBYSCORE"])
                connections = [line for line in trace.read_text().splitlines() if "connect(" in line]
                if runtime == "native":
                    self.assertEqual(len(connections), 1)
                    self.assertIn(f"htons({sandbox.port})", connections[0])
                    self.assertIn('inet_addr("127.0.0.1")', connections[0])
                    self.assertEqual(trace.read_text().count("execve("), 1)
                env["FIDELITY_CACHE_NEGATIVE"] = "1"
                negative_trace = build / (runtime + "-negative.trace")
                negative = self.command(["strace", "-f", "-e", "trace=connect", "-o", negative_trace, *argv], env=env)
                self.assertIn(b"PASS all protected/unknown cache endpoints rejected before transport", negative)
                self.assertNotIn("connect(", negative_trace.read_text())
            self.assertTrue(sandbox.cleanup_complete)
            # Load the exact native/compat stored bytes through UNMODIFIED gem5
            # classes, not through the generated component. No server/DB boots.
            original_check = '''require "rack-mini-profiler"
p = Marshal.load(File.binread(ARGV.fetch(0)))
raise "not original gem5" unless Rack::MiniProfiler::TimerStruct::Page.instance_method(:initialize).source_location.first.include?("rack-mini-profiler-5.0.0")
raise "missing real record" unless p[:request_path] == "/latest.json" && p[:sql_count] == 1
raise "lost circular page identity" unless p[:root].instance_variable_get(:@page).equal?(p)
raise "changed measured root duration" unless p[:root][:duration_milliseconds] == 1.25
puts "PASS original gem5 reads actual stored cyclic Marshal bytes"
'''
            original = self.command(["bundle", "exec", "ruby", "-e", original_check, build / (runtime + ".marshal")], cwd=ROOT / "discourse")
            self.assertIn(b"PASS original gem5 reads", original)
            results.append({"runtime": runtime, "effects": [row["command"] for row in effects], "cleanup_complete": sandbox.cleanup_complete})
        (build / "evidence.json").write_text(json.dumps({"stage": "profiler5 records/store unit ONLY", "results": results,
            "native_request_accepted": False, "page_accepted": False, "binary_sha256": digest(binary.read_bytes())}, indent=2) + "\n")
        print("Profiler unit evidence:", build)


if __name__ == "__main__":
    unittest.main()

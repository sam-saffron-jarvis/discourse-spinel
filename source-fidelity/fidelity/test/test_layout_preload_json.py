"""Exact layout escaping in an explicit standalone JSON unit context only."""
import hashlib
import json
import subprocess
from pathlib import Path
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class LayoutPreloadJsonTests(unittest.TestCase):
    def command(self, argv):
        result = subprocess.run([str(value) for value in argv], cwd=ROOT, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_exact_preload_json_helpers(self):
        build = Path(tempfile.mkdtemp(prefix="layout-preload-json-", dir=HERE / "build"))
        original_methods = build / "original-methods.rb"
        self.command(["ruby", HERE / "tools/generate_layout_preload_json.rb", original_methods])
        candidate = HERE / "compat/discourse/lib/portable_layout_preload_json.rb"
        matrix = (HERE / "test/layout_preload_json_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes(original_methods.read_bytes() + b"\n" + matrix)
        shared = build / "shared.rb"
        shared.write_bytes(candidate.read_bytes() + b"\n" + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        expected = self.command(["ruby", "--enable-frozen-string-literal", original])
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary]))
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        records = [json.loads(line) for line in expected.splitlines()[:-1]]
        self.assertEqual(len(records), 7)
        proof = json.loads((HERE / "compat/discourse/portable_layout_preload_json.json").read_text())
        self.assertEqual(hashlib.sha256(candidate.read_bytes()).hexdigest(), proof["candidate_sha256"])
        evidence = {"status": "PASS_ISOLATED_STANDALONE_LAYOUT_PRELOAD_JSON", "source_proof": proof,
                    "matched_cases": len(records), "original_shared_native_sha256": hashlib.sha256(expected).hexdigest(),
                    "native_execve_count": 1, "native_connect_count": 0,
                    "preloader_reads_and_input_immutability_checked": True,
                    "original_html_accepted": False, "native_html_accepted": False,
                    "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS isolated exact layout preload JSON original/CRuby/native: {build}")


if __name__ == "__main__":
    unittest.main()

"""Isolated genuine CSP nonce/provider/helper dependency; no Rails boot/effects."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


class CspNonceTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=120,
                                env={**os.environ, "RAILS_ENV": "production"})
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_genuine_nonce_helper_and_injector(self):
        build = Path(tempfile.mkdtemp(prefix="csp-nonce-", dir=HERE / "build"))
        original_csp = build / "original-csp.rb"
        original_preload = build / "original-preload.rb"
        self.command(["ruby", HERE / "tools/generate_csp_nonce.rb", original_csp])
        self.command(["ruby", HERE / "tools/generate_asset_preloads.rb", original_preload])
        context = (HERE / "test/asset_preload_unit_context.rb").read_bytes()
        matrix = (HERE / "test/csp_nonce_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes(b'''require "erb"
require "active_support"
require "active_support/core_ext/string/output_safety"
require "active_support/core_ext/object/blank"
require "fast_blank"
def unit_safe_result?(value)
  value.is_a?(ActiveSupport::SafeBuffer) && value.html_safe?
end
def fragment_record(fragment)
  raise "original helper lost safe type" unless unit_safe_result?(fragment)
  {text: fragment.to_s, kind: "trusted_html"}
end
''' + original_preload.read_bytes() + b"\n" + original_csp.read_bytes() + b"\n" + context + b"\n" + matrix)
        candidate = HERE / "compat/discourse/lib/portable_csp_nonce.rb"
        shared = build / "shared.rb"
        shared.write_bytes((ROOT / "roundhouse/runtime/ruby/action_view/html_fragment.rb").read_bytes() + b"\n" +
            (HERE / "compat/discourse/lib/portable_asset_preloads.rb").read_bytes() + b"\n" + candidate.read_bytes() + b'''
def unit_safe_result?(value)
  value.is_a?(ActionView::HtmlFragment) && value.html_safe?
end
def fragment_record(fragment)
  raise "candidate helper lost safe type" unless unit_safe_result?(fragment)
  {text: fragment.to_s, kind: "trusted_html"}
end
''' + context + b"\n" + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect,getrandom", "-o", trace, binary]))
        trace_text = trace.read_text()
        self.assertEqual(trace_text.count("execve("), 1)
        self.assertNotIn("connect(", trace_text)
        self.assertIn("getrandom(", trace_text)
        rows = [json.loads(line) for line in expected.splitlines()[:-1]]
        self.assertEqual(len(rows), 5)
        self.assertEqual([row["same_body"] for row in rows], [False, False, True, True, False])
        self.assertTrue(all("UNIT_NORMALIZED_NONCE" in row["parts"][0] for row in rows))
        proof = json.loads((HERE / "compat/discourse/portable_csp_nonce.json").read_text())
        self.assertEqual(proof["candidate_sha256"], sha(candidate.read_bytes()))
        mutation_failures = {}
        for name, old, new, error in (
            ("wrong_csp_nonce", "script-src 'nonce-#{nonce}' ", "script-src 'nonce-unit-wrong' ", b"enforced CSP nonce wrong"),
            ("reused_random_nonce", 'SecureRandom.alphanumeric(25)', '("A" * 25)', b"reused actual random nonce"),
        ):
            mutant = build / (name + ".rb")
            code = shared.read_text()
            self.assertIn(old, code)
            mutant.write_text(code.replace(old, new, 1))
            mutant_binary = build / name
            self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", mutant, "-o", mutant_binary])
            rejected = subprocess.run([str(mutant_binary)], capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertIn(error, rejected.stderr, name)
            mutation_failures[name] = rejected.returncode
        evidence = {"status": "PASS_ISOLATED_CSP_NONCE_HELPER_INJECTOR", "source_proof": proof,
                    "original_shared_native_normalized_sha256": sha(expected), "matched_contexts": [row["mode"] for row in rows],
                    "normalization": "Only freshly generated nonce bytes, AFTER exact within-run format, memoization, body/CSP equality and uniqueness checks",
                    "genuine_randomness": True, "native_execve_count": 1, "native_connect_count": 0,
                    "native_getrandom_observed": True, "body_and_resource_identity_checks": True,
                    "native_mutation_controls": mutation_failures,
                    "original_html_accepted": False, "native_html_accepted": False,
                    "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS isolated source nonce helper/injector original/CRuby/native: {build}")


if __name__ == "__main__":
    unittest.main()

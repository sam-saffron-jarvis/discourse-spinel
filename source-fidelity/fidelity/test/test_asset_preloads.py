"""Write-free source-backed helper dependency; never a real HTML request."""
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


class AssetPreloadsTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT, timeout=120):
        process = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True,
                                 timeout=timeout, env={**os.environ, "RAILS_ENV": "production"})
        self.assertEqual(process.returncode, 0, process.stderr.decode(errors="replace"))
        return process.stdout

    def test_original_shared_native_asset_tags_and_resource_side_effects(self):
        build = Path(tempfile.mkdtemp(prefix="asset-preloads-", dir=HERE / "build"))
        original_projection = build / "original-methods.rb"
        self.command(["ruby", HERE / "tools/generate_asset_preloads.rb", original_projection])
        candidate = HERE / "compat/discourse/lib/portable_asset_preloads.rb"
        proof = json.loads((HERE / "compat/discourse/portable_asset_preloads.json").read_text())
        self.assertEqual(proof["candidate_sha256"], sha(candidate.read_bytes()))
        graph = (HERE / "compat/discourse/lib/portable_ember_asset_graph.rb").read_bytes()
        matrix = ((HERE / "test/asset_preload_unit_context.rb").read_bytes() + b"\n" +
                  (HERE / "test/asset_preloads_matrix.rb").read_bytes())
        original = build / "original.rb"
        original.write_bytes(b'''require "erb"
require "active_support"
require "active_support/core_ext/string/output_safety"
require "active_support/core_ext/object/blank"
def fragment_record(fragment)
  raise "original helper lost safe result type" unless fragment.is_a?(ActiveSupport::SafeBuffer) && fragment.html_safe?
  {text: fragment.to_s, safe: fragment.html_safe?, kind: "trusted_html"}
end
''' + graph + b"\n" + original_projection.read_bytes() + b"\n" + matrix)
        shared = build / "shared.rb"
        runtime = ROOT / "roundhouse/runtime/ruby/action_view/html_fragment.rb"
        owner_matrix = ROOT / "roundhouse/runtime/ruby/test/action_view/html_fragment_native_matrix.rb"
        shared.write_bytes(runtime.read_bytes() + b"\n" + owner_matrix.read_bytes() + b"\n" + graph + b"\n" + candidate.read_bytes() + b'''
def fragment_record(fragment)
  raise "typed helper lost safe result type" unless fragment.is_a?(ActionView::HtmlFragment) && fragment.html_safe?
  raise "safe marking not idempotent" unless fragment.html_safe.equal?(fragment)
  {text: fragment.to_s, safe: fragment.html_safe?, kind: "trusted_html"}
end
''' + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        source = HERE / "build/recovery24-frontend/source"
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original, source], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared, source]))
        self.assertEqual(expected, self.command([binary, source]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary, source]))
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        first, changed, message = expected.splitlines()
        first = json.loads(first)
        self.assertEqual(len(first["rows"]), 5)
        self.assertTrue(all(row["safe"] and row["kind"] == "trusted_html" for row in first["rows"]))
        self.assertNotEqual(first["rows"][0], json.loads(changed)["changed"])
        self.assertIn(b"PASS isolated source helper", message)
        # Executable mutations: a typed fragment with wrong escaping/nonce/order
        # must still fail, not pass merely because its wrapper is trusted.
        mutation_failures = {}
        for name, old, new, error in (
            ("unescaped_attrs", 'ERB::Util.html_escape(v)', 'v', b"attribute escaping absent"),
            ("wrong_nonce", '    @nonce\n', '    "unit-wrong-nonce"\n', b"wrong nonce"),
            ("reversed_resources", 'links << %Q(', 'links.unshift %Q(', b"resource ordering/duplicates/module side effects changed"),
        ):
            mutant = build / (name + ".rb")
            code = shared.read_text()
            self.assertIn(old, code)
            mutant.write_text(code.replace(old, new, 1))
            mutant_binary = build / name
            self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", mutant, "-o", mutant_binary])
            rejected = subprocess.run([str(mutant_binary), str(source)], capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertIn(error, rejected.stderr, name)
            mutation_failures[name] = rejected.returncode
        missing_root = build / "missing-genuine-files"
        manifest = Path("frontend/discourse/dist/manifest/manifest.json")
        (missing_root / manifest).parent.mkdir(parents=True)
        (missing_root / manifest).write_bytes((source / manifest).read_bytes())
        missing_failures = {}
        for name, argv, cwd in (
            ("original", ["bundle", "exec", "ruby", original, missing_root], ROOT / "discourse"),
            ("shared", ["ruby", shared, missing_root], ROOT),
            ("native", [binary, missing_root], ROOT),
        ):
            rejected = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertIn(b"No such file or directory", rejected.stderr, name)
            self.assertEqual(rejected.stdout, b"", name)
            missing_failures[name] = rejected.returncode
        evidence = {"status": "PASS_ISOLATED_ASSET_PRELOAD_HELPERS", "source_proof": proof,
                    "original_shared_native_sha256": sha(expected), "binary_sha256": sha(binary.read_bytes()),
                    "genuine_asset_files_read": len(first["genuine_assets"]),
                    "genuine_asset_bytes": sum(row[1] for row in first["genuine_assets"]),
                    "unit_context": "Explicit supplied URL map and nonce values, isolated collector; not production/runtime oracle state",
                    "safe_result_type": "Original SafeBuffer vs explicit typed HtmlFragment, never ordinary String",
                    "native_execve_count": 1, "native_connect_count": 0,
                    "native_mutation_controls": mutation_failures, "missing_genuine_file_controls": missing_failures,
                    "original_html_accepted": False, "native_html_accepted": False,
                    "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS isolated original/CRuby/native asset preload helper: {build}")


if __name__ == "__main__":
    unittest.main()

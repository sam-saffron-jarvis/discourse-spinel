"""Real file-backed resolver + original URL rewriting; no Rails boot/effects."""
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


class AssetUrlsTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT, timeout=120):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=timeout,
                                env={**os.environ, "RAILS_ENV": "production"})
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_propshaft_shared_native_file_backed_urls(self):
        build = Path(tempfile.mkdtemp(prefix="asset-urls-", dir=HERE / "build"))
        original_methods = build / "original-methods.rb"
        self.command(["ruby", HERE / "tools/generate_asset_urls.rb", original_methods])
        context = (HERE / "test/asset_url_unit_context.rb").read_bytes()
        matrix = (HERE / "test/asset_urls_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes((HERE / "test/asset_urls_original_backend.rb").read_bytes() + b"\n" +
            original_methods.read_bytes() + b"\n" + context + b'''
class UnitOriginalUrlHelper < UnitUrlHelper
  include UnitOriginalActivation
end
''' + matrix)
        shared = build / "shared.rb"
        response = (HERE / "compat/framework/portable_json_response_middleware.rb").read_text()
        declaration = response[:response.index("# frozen_string_literal: true\n\nmodule MarkdownEndpoint")]
        runtime = ROOT / "roundhouse/runtime/ruby/action_view/source_asset_paths.rb"
        candidate = HERE / "compat/discourse/lib/portable_asset_urls.rb"
        shared.write_bytes(runtime.read_bytes() + b"\n" + declaration.encode() + b"\n" + candidate.read_bytes() + b"\n" + context + b'''
def new_unit_url_helper(settings, roots, version, encoding)
  load_path = ActionView::SourceAssetLoadPath.new(roots, version)
  resolver = ActionView::SourceAssetResolver.new(load_path, "/assets")
  paths = ActionView::SourceAssetPaths.new(resolver, settings.relative_url_root, settings.cdn_url)
  UnitUrlHelper.new(settings, paths, encoding)
end
def missing_asset_error?(error)
  error.is_a?(Propshaft::MissingAssetError)
end
''' + matrix)
        shared.with_suffix(".rbs").write_bytes(runtime.with_suffix(".rbs").read_bytes())
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        source = HERE / "build/recovery24-frontend/source"
        extra = build / "unit-path-fixtures"
        extra.mkdir()
        # Explicit unit logical names with real existing source bytes; these
        # are not claimed to be production assets or a substitute build.
        genuine = (source / "frontend/discourse/scripts/js/browser-detect.js").read_bytes()
        for name in ("unit space&quote'雪.js", "unit-special-abcdefgh.digested.js", "unit-precedence.js"):
            (extra / name).write_bytes(genuine)
        (extra / "nested").mkdir()
        (extra / "nested/unit-precedence.js").write_bytes((source / "frontend/discourse/scripts/js/browser-update.js").read_bytes())
        priority_a, priority_b = build / "priority-a", build / "priority-b"
        for path, data in ((priority_a, genuine), (priority_b, (source / "frontend/discourse/scripts/js/browser-update.js").read_bytes())):
            path.mkdir()
            (path / "unit-precedence.js").write_bytes(data)
        argv = [source, extra, priority_a, priority_b]
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original, *argv], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared, *argv]))
        self.assertEqual(expected, self.command([binary, *argv]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect,openat", "-o", trace, binary, *argv]))
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        self.assertIn("browser-detect.js", trace.read_text())
        records = [json.loads(line) for line in expected.splitlines()[:-1]]
        self.assertEqual(len(records), 13)
        self.assertEqual(len({tuple(row["paths"]) for row in records[1:10]}), 7)
        mutations = {}
        for name, old, new, error in (
            ("wrong_digest", 'Digest::SHA1.hexdigest', 'Digest::SHA256.hexdigest', b"wrong source-content digest"),
            ("missing_root", 'source = File.join(root, source)', 'source = source', b"root omitted"),
            ("wrong_brotli", 'path = path.sub("/assets/js/", "/assets/br/")', 'path = path', b"wrong original S3/root/brotli URL"),
            ("wrong_precedence", 'mapped[logical_path] ||=', 'mapped[logical_path] =', b"wrong file-root priority"),
        ):
            code = shared.read_text()
            self.assertIn(old, code)
            mutant = build / (name + ".rb")
            mutant.write_text(code.replace(old, new, 1))
            mutant_binary = build / name
            self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", mutant, "-o", mutant_binary])
            rejected = subprocess.run([str(mutant_binary), *[str(value) for value in argv]], capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertIn(error, rejected.stderr, name)
            mutations[name] = rejected.returncode
        proof = json.loads((HERE / "compat/discourse/portable_asset_urls.json").read_text())
        self.assertEqual(proof["candidate_sha256"], sha(candidate.read_bytes()))
        evidence = {"status": "PASS_ISOLATED_REAL_FILE_ASSET_URLS", "source_proof": proof,
                    "original_shared_native_sha256": sha(expected), "matched_records": len(records),
                    "native_execve_count": 1, "native_connect_count": 0,
                    "real_original_resolver": "Propshaft::LoadPath + Asset + Resolver::Dynamic + actual ActionView asset_path",
                    "unit_settings_only": True, "genuine_asset_file_reads": records[0]["genuine_asset_reads"],
                    "native_mutation_controls": mutations, "original_html_accepted": False,
                    "native_html_accepted": False, "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS real file-backed original Propshaft/shared/native URL helper: {build}")


if __name__ == "__main__":
    unittest.main()

"""Execute a live manifest graph dependency, never HTML/page acceptance."""
import copy
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent
PIN = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
MANIFEST = Path("frontend/discourse/dist/manifest/manifest.json")


def sha(data):
    return hashlib.sha256(data).hexdigest()


class EmberAssetGraphTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT, timeout=120):
        completed = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True,
                                   timeout=timeout, env={**os.environ, "RAILS_ENV": "production"})
        self.assertEqual(completed.returncode, 0, completed.stderr.decode(errors="replace"))
        return completed.stdout

    def test_live_original_shared_native_manifest_graph(self):
        build = Path(tempfile.mkdtemp(prefix="ember-asset-graph-", dir=HERE / "build"))
        self.command(["ruby", HERE / "tools/generate_ember_asset_graph.rb"])
        source = self.command(["git", "-C", ROOT / "discourse", "show", f"{PIN}:lib/ember_assets.rb"])
        self.assertEqual(source, (ROOT / "discourse/lib/ember_assets.rb").read_bytes())
        candidate = HERE / "compat/discourse/lib/portable_ember_asset_graph.rb"
        proof = json.loads((HERE / "compat/discourse/portable_ember_asset_graph.json").read_text())
        self.assertEqual(proof["source_sha256"], sha(source))
        self.assertEqual(proof["candidate_sha256"], sha(candidate.read_bytes()))
        common = b'''require "digest"
def emit_graph(root, graph)
  asset_dir = "#{root}/frontend/discourse/dist/assets"
  if File.directory?(asset_dir)
    names = (graph["script_chunks"].values.flatten + graph["import_map"].values).uniq.sort
    graph["asset_files"] = names.map do |name|
      data = File.binread("#{asset_dir}/#{name}.js")
      [name, data.bytesize, Digest::SHA256.hexdigest(data)]
    end
  end
  puts JSON.generate(graph)
end
'''
        original = build / "original.rb"
        original.write_bytes(common + b'''require "json"
require "set"
require "pathname"
require "active_support"
require "active_support/current_attributes"
require "active_support/string_inquirer"
# Only filesystem/environment collaborators for this pure dependency test.
# No Rails application, controller, PG, setting or callback is substituted.
module Rails
  def self.root
    Pathname.new(ENV.fetch("FIDELITY_GRAPH_ROOT"))
  end
  def self.env
    ActiveSupport::StringInquirer.new("production")
  end
end
require ARGV.shift
ARGV.each do |root|
  ENV["FIDELITY_GRAPH_ROOT"] = root
  EmberAssets.clear_cache!
  emit_graph(root, {"script_chunks" => EmberAssets.script_chunks, "import_map" => EmberAssets.import_map})
end
''')
        shared = build / "shared.rb"
        shared.write_bytes(candidate.read_bytes() + b"\n" + common + b'''\nrequire "json"
ARGV.each do |root|
  manifest = JSON.parse(File.read("#{root}/frontend/discourse/dist/manifest/manifest.json"))
  emit_graph(root, {"script_chunks" => PortableEmberAssetGraph.script_chunks(manifest),
                   "import_map" => PortableEmberAssetGraph.import_map(manifest)})
end
''')
        # Keep the paired signature beside the generated compilation unit.
        shared.with_suffix(".rbs").write_bytes(candidate.with_suffix(".rbs").read_bytes())
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        built = HERE / "build/recovery24-frontend/source"
        manifest_bytes = (built / MANIFEST).read_bytes()
        self.assertEqual(sha(manifest_bytes), "353d6bcfe09088e3e998274f76ef246b174bb989709ad327f260a976064b4b1e")
        roots = [built]
        names = ["genuine_rolldown_manifest"]
        cases = []
        graph = {"entrypoints": {"app.js": "assets/root.js"},
                 "dynamicEntrypoints": {"lazy.js": "assets/lazy.js"},
                 "chunks": {"assets/root.js": {"imports": ["assets/left.js", "assets/right.js"]},
                            "assets/left.js": {"imports": ["assets/shared.js"]},
                            "assets/right.js": {"imports": ["assets/shared.js"]},
                            "assets/shared.js": {"imports": ["assets/root.js"]},
                            "assets/lazy.js": {"imports": ["assets/shared.js"]}},
                 "importMap": {"assets/stable.js": "assets/root.js"}}
        cases.append(("cycle_diamond_dynamic_order", graph))
        changed = copy.deepcopy(graph)
        changed["dynamicEntrypoints"]["app.js"] = "assets/lazy.js"
        changed["importMap"]["assets/stable.js"] = "assets/right.js"
        cases.append(("live_collision_and_import_map_change", changed))
        cases.append(("missing_chunk_retains_original_root", {"entrypoints": {"missing.js": "assets/missing.js"},
                      "dynamicEntrypoints": {}, "chunks": {}}))
        cases.append(("no_imports_or_mapping", {"entrypoints": {"prefix.js.js": "assets/not-js.css"},
                      "dynamicEntrypoints": {}, "chunks": {"assets/not-js.css": {}}}))
        cases.append(("empty_graph", {"entrypoints": {}, "dynamicEntrypoints": {}, "chunks": {}, "importMap": {}}))
        for name, data in cases:
            root = build / name
            (root / MANIFEST).parent.mkdir(parents=True)
            (root / MANIFEST).write_text(json.dumps(data))
            roots.append(root)
            names.append(name)
        # A genuine manifest again in the SAME process detects stale per-fixture
        # traversal state or captured output. Original cache is genuinely cleared.
        roots.append(built)
        names.append("genuine_again_after_changed_inputs")
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original,
                                 ROOT / "discourse/lib/ember_assets.rb", *roots], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared, *roots]))
        self.assertEqual(expected, self.command([binary, *roots]))
        outputs = [json.loads(line) for line in expected.splitlines()]
        self.assertEqual(outputs[0], outputs[-1])
        self.assertTrue(outputs[0]["script_chunks"]["discourse"])
        self.assertTrue(outputs[0]["import_map"])
        self.assertTrue(outputs[0]["asset_files"])
        self.assertTrue(all(size > 0 and len(digest) == 64 for _, size, digest in outputs[0]["asset_files"]))
        self.assertEqual(outputs[1]["script_chunks"]["app"], ["root", "left", "shared", "right"])
        self.assertEqual(outputs[1]["script_chunks"]["lazy"], ["lazy", "shared", "root", "left", "right"])
        self.assertEqual(outputs[2]["script_chunks"]["app"], outputs[1]["script_chunks"]["lazy"])
        self.assertNotEqual(outputs[1]["import_map"], outputs[2]["import_map"])
        self.assertEqual(outputs[3]["script_chunks"], {"missing": ["missing"]})
        self.assertEqual(outputs[4]["script_chunks"], {"prefix.js": ["not-js.css"]})
        self.assertEqual(outputs[5], {"script_chunks": {}, "import_map": {}})
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary, *roots]))
        trace_text = trace.read_text()
        self.assertEqual(trace_text.count("execve("), 1)
        self.assertNotIn("connect(", trace_text)
        self.assertEqual(manifest_bytes, (built / MANIFEST).read_bytes())
        self.assertEqual(source, (ROOT / "discourse/lib/ember_assets.rb").read_bytes())
        # A real manifest with an empty asset directory must fail in all three
        # runtimes, not return invented assets or an incomplete success record.
        missing = build / "missing-genuine-asset-files"
        (missing / MANIFEST).parent.mkdir(parents=True)
        (missing / MANIFEST).write_bytes(manifest_bytes)
        (missing / "frontend/discourse/dist/assets").mkdir()
        missing_rejections = {}
        for name, argv, cwd in (
            ("original", ["bundle", "exec", "ruby", original, ROOT / "discourse/lib/ember_assets.rb", missing], ROOT / "discourse"),
            ("shared", ["ruby", shared, missing], ROOT), ("native", [binary, missing], ROOT),
        ):
            rejected = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=30,
                                      env={**os.environ, "RAILS_ENV": "production"})
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertEqual(rejected.stdout, b"", name)
            self.assertIn(b"No such file or directory", rejected.stderr, name)
            missing_rejections[name] = rejected.returncode
        evidence = {"status": "PASS_PURE_EMBER_ASSET_GRAPH", "source_proof": proof,
                    "manifest_sha256": sha(manifest_bytes), "candidate_sha256": sha(candidate.read_bytes()),
                    "binary_sha256": sha(binary.read_bytes()), "matched_cases": names,
                    "original_helper": "Full pinned EmberAssets, production environment/filesystem collaborators only",
                    "genuine_entrypoints": len(outputs[0]["script_chunks"]),
                    "genuine_import_map_entries": len(outputs[0]["import_map"]),
                    "genuine_asset_files_read_and_hashed": len(outputs[0]["asset_files"]),
                    "genuine_asset_file_bytes": sum(row[1] for row in outputs[0]["asset_files"]),
                    "original_shared_native_output_sha256": sha(expected),
                    "native_execve_count": 1, "native_connect_count": 0,
                    "missing_genuine_asset_rejected_before_output": missing_rejections,
                    "pg_or_cache_effects": False, "original_html_accepted": False,
                    "native_html_accepted": False, "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS pure original/CRuby/native asset graph ({len(names)} live cases); not HTML: {build}")


if __name__ == "__main__":
    unittest.main()

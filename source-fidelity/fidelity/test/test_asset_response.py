"""Actual read-only Propshaft Rack method responses; no socket/listener or Rails boot."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


def emit_original_compiler_patch(command, build):
    # Select only the ACTUAL Discourse compiler prepend, not a hand-built
    # identity compiler or its unrelated Helper rescue/watch lifecycle.
    extractor = r'''require "prism"
require "json"
require "digest"
require "open3"
root = ARGV.fetch(0)
path = "lib/freedom_patches/propshaft_patches.rb"
source, status = Open3.capture2("git", "-C", "#{root}/discourse", "show", "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8:#{path}")
raise "compiler patch changed" unless status.success? && source.b == File.binread("#{root}/discourse/#{path}")
node = Prism.parse(source).value.statements.body.find { |n| n.is_a?(Prism::CallNode) && n.name == :prepend && n.receiver.slice == "Propshaft::Compiler::SourceMappingUrls" }
raise "original compiler patch missing" unless node
File.write(ARGV[1], node.slice + "\n")
File.write(ARGV[2], JSON.pretty_generate({source: path, source_sha256: Digest::SHA256.hexdigest(source), start_byte: node.location.start_offset,
  end_byte: node.location.end_offset, text_sha256: Digest::SHA256.hexdigest(node.slice)}) + "\n")
'''
    patch = build / "original-compiler-patch.rb"
    command(["ruby", "-e", extractor, ROOT, patch, build / "compiler-patch.json"])
    return patch


class AssetResponseTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=120,
                                env={**os.environ, "RAILS_ENV": "production"})
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_readonly_js_responses(self):
        build = Path(tempfile.mkdtemp(prefix="asset-response-", dir=HERE / "build"))
        self.command(["ruby", HERE / "tools/generate_asset_urls.rb", build / "original-urls-unused.rb"])
        patch = emit_original_compiler_patch(self.command, build)
        matrix = (HERE / "test/asset_response_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes((HERE / "test/asset_response_original_backend.rb").read_bytes() + b"\n" + patch.read_bytes() + b"\n" + matrix)
        paths = ROOT / "roundhouse/runtime/ruby/action_view/source_asset_paths.rb"
        response = ROOT / "roundhouse/runtime/ruby/action_view/source_asset_response.rb"
        shared = build / "shared.rb"
        shared.write_bytes(paths.read_bytes() + b"\n" + response.read_bytes() + b'''
def new_unit_asset_response(app, roots, version, sweep_cache = false, watcher_profile = "none")
  ActionView::SourceAssetResponse.new(app, ActionView::SourceAssetLoadPath.new(roots, version), "/assets/", sweep_cache, watcher_profile)
end
''' + matrix)
        shared.with_suffix(".rbs").write_bytes(paths.with_suffix(".rbs").read_bytes() + b"\n" + response.with_suffix(".rbs").read_bytes())
        profile_controls = b'''
# Candidate's explicitly unsupported profiles must refuse, never silently skip
# an applicable compiler or watcher. These are labelled unit negative inputs.
app = lambda { |_env| [418, {"content-type" => "text/plain"}, ["unit fallback"]] }
load_path = ActionView::SourceAssetLoadPath.new([ARGV.fetch(1)], "2-unit-response")
begin
  ActionView::SourceAssetResponse.new(app, load_path, "/assets/", true)
  raise "watcher silently suppressed"
rescue ArgumentError => error
  raise unless error.message == "unsupported asset cache watcher profile"
end
server = ActionView::SourceAssetResponse.new(app, load_path, "/assets/", false)
%w[unit-with-map.js unit-css.css].each do |name|
  digest = Digest::SHA1.hexdigest("#{File.binread(File.join(ARGV.fetch(1), name))}2-unit-response")[0, 8]
  requested = name.sub(/\\.(js|css)$/, "-#{digest}.\\\\1")
  begin
    server.call({"REQUEST_METHOD" => "GET", "PATH_INFO" => "/assets/#{requested}"})
    raise "unsupported compilation/MIME silently accepted"
  rescue ArgumentError => error
    raise unless error.message.start_with?("unsupported nonidentity source-map compilation") || error.message.start_with?("unsupported non-JavaScript asset response")
  end
end
'''
        shared.write_bytes(shared.read_bytes() + profile_controls)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        source = HERE / "build/recovery24-frontend/source"
        extra = build / "unit-escaped-path"
        extra.mkdir()
        (extra / "unit space&雪-abcdefgh.digested.js").write_bytes((source / "frontend/discourse/scripts/js/browser-detect.js").read_bytes())
        (extra / "unit-with-map.js").write_bytes(b"// labelled unit negative compiler input\n//# sourceMappingURL=unit.map\n")
        (extra / "unit-css.css").write_bytes(b"/* labelled unit negative MIME input */")
        argv = [source, extra]
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original, *argv], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared, *argv]))
        self.assertEqual(expected, self.command([binary, *argv]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect,openat", "-o", trace, binary, *argv]))
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        record = json.loads(expected.splitlines()[0])
        self.assertEqual(len(record["responses"]), 10)
        self.assertTrue(record["null_watcher_refresh_verified"])
        self.assertEqual([row["status"] for row in record["responses"]], [200, 200, 200, 200, 404, 404, 418, 418, 200, 404])
        mutations = {}
        for name, old, new, error in (
            ("head_body_leak", 'method == "HEAD" ? [] : [compiled_content]', '[compiled_content]', b"HEAD leaked body"),
            ("stale_digest_accepted", 'asset.fresh?(digest)', 'true', b"missing/stale asset not 404"),
            ("wrong_cache_header", 'public, max-age=31536000, immutable', 'private', b"immutable cache header lost"),
            ("missing_percent_decode", 'path = URI.decode_www_form_component(path.delete_prefix(@prefix))', 'path = path.delete_prefix(@prefix)', b"genuine file response not 200"),
            ("suppressed_null_watcher", '@load_path.refresh! if @refresh_each_call', 'nil', b"NullFileWatcher did not invalidate stale digest"),
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
        evidence = {"status": "PASS_ISOLATED_READONLY_ASSET_RESPONSES", "source_proof": proof,
                    "compiler_patch": json.loads((build / "compiler-patch.json").read_text()),
                    "native_runtime_sha256": {str(path.relative_to(ROOT)): hashlib.sha256(path.read_bytes()).hexdigest()
                                              for path in (paths, paths.with_suffix(".rbs"), response, response.with_suffix(".rbs"))},
                    "response_source_sha256": proof["framework_sources"]["propshaft-1.3.2"]["files"]["lib/propshaft/server.rb"],
                    "original_shared_native_sha256": hashlib.sha256(expected).hexdigest(),
                    "native_execve_count": 1, "native_connect_count": 0, "no_listener_or_service": True,
                    "unit_sweeper_disabled_profile": True, "actual_null_watcher_refresh_profile_verified": True,
                    "active_support_evented_watcher_accepted": False, "nonidentity_compilation_refuses": True,
                    "native_mutation_controls": mutations, "malformed_percent_decode_refuses": True,
                    "pinned_rack_version": "2.2.24",
                    "original_html_accepted": False, "native_html_accepted": False,
                    "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS actual Propshaft/shared/native read-only asset Rack responses: {build}")


if __name__ == "__main__":
    unittest.main()

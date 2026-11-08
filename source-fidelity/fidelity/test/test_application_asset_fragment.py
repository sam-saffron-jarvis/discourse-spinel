"""Concrete pinned layout fragment, actual ActionView ERB vs typed native composition."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from test_asset_response import emit_original_compiler_patch

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


def sha(data):
    return hashlib.sha256(data).hexdigest()


class ApplicationAssetFragmentTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT, timeout=120):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=timeout,
                                env={**os.environ, "RAILS_ENV": "production"})
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_real_resolver_helpers_and_original_erb_fragment(self):
        build = Path(tempfile.mkdtemp(prefix="application-asset-fragment-", dir=HERE / "build"))
        generated = {name: build / (name + ".rb") for name in ("urls", "preloads", "csp", "policy", "erb", "preload_erb", "importmap_erb")}
        self.command(["ruby", HERE / "tools/generate_asset_urls.rb", generated["urls"]])
        self.command(["ruby", HERE / "tools/generate_asset_preloads.rb", generated["preloads"]])
        self.command(["ruby", HERE / "tools/generate_csp_nonce.rb", generated["csp"]])
        self.command(["ruby", HERE / "tools/generate_csp_policy.rb", generated["policy"]])
        fragment = build / "original-fragment.html.erb"
        self.command(["bundle", "exec", "ruby", HERE / "tools/generate_application_asset_fragment.rb", fragment, generated["erb"]], cwd=ROOT / "discourse")
        preload_fragment = build / "original-preload-fragment.html.erb"
        self.command(["bundle", "exec", "ruby", HERE / "tools/generate_application_preload_fragment.rb", preload_fragment, generated["preload_erb"]], cwd=ROOT / "discourse")
        importmap_fragment = build / "original-importmap-fragment.html.erb"
        self.command(["bundle", "exec", "ruby", HERE / "tools/generate_application_importmap_fragment.rb", importmap_fragment, generated["importmap_erb"]], cwd=ROOT / "discourse")
        preload_helpers = (HERE / "compat/discourse/lib/portable_layout_preload_json.rb").read_bytes()
        original = build / "original.rb"
        native_context = (HERE / "test/asset_url_unit_context.rb").read_bytes()
        layout_context = (HERE / "test/application_asset_fragment_context.rb").read_bytes()
        graph = (HERE / "compat/discourse/lib/portable_ember_asset_graph.rb").read_bytes()
        matrix = (HERE / "test/application_asset_fragment_matrix.rb").read_bytes()
        compiler_patch = emit_original_compiler_patch(self.command, build)
        csp_context = (HERE / "test/csp_policy_unit_context.rb").read_bytes()
        csp_original = (HERE / "test/csp_policy_original_backend.rb").read_bytes() + b"\n" + generated["policy"].read_bytes() + b"\n" + csp_context
        csp_runtime = ROOT / "roundhouse/runtime/ruby/action_dispatch/content_security_policy.rb"
        csp_shared = csp_runtime.read_bytes() + b"\n" + (HERE / "compat/discourse/lib/portable_csp_policy.rb").read_bytes() + b"\n" + csp_context + b"\n" + (HERE / "test/csp_policy_shared_backend.rb").read_bytes()
        original.write_bytes((HERE / "test/asset_urls_original_backend.rb").read_bytes() + b"\n" +
            (HERE / "test/asset_response_original_backend.rb").read_bytes() + b"\n" + compiler_patch.read_bytes() + b"\n" + csp_original + b'''
require "action_view/template/handlers/erb/erubi"
require "active_support/core_ext/string/output_safety"
require "json"
json_method = Hash.instance_method(:to_json).source_location
raise "unsupported minimal reference JSON encoder" unless json_method && json_method.first.include?("/json-")
''' + graph + b"\n" + generated["urls"].read_bytes() + b"\n" + native_context + b"\n" +
            generated["preloads"].read_bytes() + b"\n" + generated["csp"].read_bytes() + b"\n" +
            generated["erb"].read_bytes() + b"\n" + generated["preload_erb"].read_bytes() + b"\n" +
            generated["importmap_erb"].read_bytes() + b"\n" + preload_helpers + b"\n" + layout_context + b'''
class UnitOriginalUrlHelper < UnitUrlHelper
  include UnitOriginalActivation
end
class UnitOriginalLayoutAssetHelper < UnitLayoutAssetHelper
  include ActionView::Helpers::OutputSafetyHelper
  include UnitOriginalActivation
end
def new_layout_asset_helper(settings, roots, version, encoding, chunks, unit_staff, cacheable)
  base = new_unit_url_helper(settings, roots, version, encoding)
  EmberAssets.script_chunks = chunks
  helper = UnitOriginalLayoutAssetHelper.new(settings, base.asset_paths, encoding, chunks, unit_staff, cacheable)
  helper.activate
  helper
end
def unit_fragment?(fragment)
  fragment.is_a?(ActiveSupport::SafeBuffer) && fragment.html_safe?
end
''' + matrix)
        shared = build / "shared.rb"
        candidate = HERE / "compat/discourse/lib/portable_application_asset_fragment.rb"
        shared.write_bytes(csp_shared + b"\n" + (ROOT / "roundhouse/runtime/ruby/action_view/source_asset_paths.rb").read_bytes() + b"\n" +
            (ROOT / "roundhouse/runtime/ruby/action_view/source_asset_response.rb").read_bytes() + b"\n" +
            (ROOT / "roundhouse/runtime/ruby/action_view/html_fragment.rb").read_bytes() + b"\n" + graph + b"\n" +
            (HERE / "compat/discourse/lib/portable_asset_urls.rb").read_bytes() + b"\n" + native_context + b"\n" +
            (HERE / "compat/discourse/lib/portable_asset_preloads.rb").read_bytes() + b"\n" +
            (HERE / "compat/discourse/lib/portable_csp_nonce.rb").read_bytes() + b"\n" + candidate.read_bytes() + b"\n" +
            (HERE / "compat/discourse/lib/portable_application_preload_fragment.rb").read_bytes() + b"\n" +
            (HERE / "compat/discourse/lib/portable_application_importmap_fragment.rb").read_bytes() + b"\n" + preload_helpers + b"\n" + layout_context + b'''
def new_layout_asset_helper(settings, roots, version, encoding, chunks, unit_staff, cacheable)
  load_path = ActionView::SourceAssetLoadPath.new(roots, version)
  resolver = ActionView::SourceAssetResolver.new(load_path, "/assets")
  paths = ActionView::SourceAssetPaths.new(resolver, settings.relative_url_root, settings.cdn_url)
  UnitLayoutAssetHelper.new(settings, paths, encoding, chunks, unit_staff, cacheable)
end
def new_unit_asset_response(app, roots, version, sweep_cache = false, watcher_profile = "none")
  ActionView::SourceAssetResponse.new(app, ActionView::SourceAssetLoadPath.new(roots, version), "/assets/", sweep_cache, watcher_profile)
end
def missing_asset_error?(error)
  error.is_a?(Propshaft::MissingAssetError)
end
def unit_fragment?(fragment)
  fragment.is_a?(ActionView::HtmlFragment) && fragment.html_safe?
end
''' + matrix)
        shared.with_suffix(".rbs").write_bytes(csp_runtime.with_suffix(".rbs").read_bytes())
        logs = build / "owned-policy-logs"
        logs.mkdir(mode=0o700)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        source = HERE / "build/recovery24-frontend/source"
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original, source, logs], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared, source, logs]))
        self.assertEqual(expected, self.command([binary, source, logs]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect,getrandom,openat", "-o", trace, binary, source, logs]))
        trace_text = trace.read_text()
        self.assertEqual(trace_text.count("execve("), 1)
        self.assertNotIn("connect(", trace_text)
        self.assertIn("getrandom(", trace_text)
        self.assertIn("browser-detect.js", trace_text)
        records = [json.loads(line) for line in expected.splitlines()[:-1]]
        self.assertEqual(len(records), 5)
        self.assertGreater(records[1]["modules"], records[0]["modules"])
        self.assertGreaterEqual(len(records[3]["delivered_assets"]), 53)
        mutations = {}
        for name, old, new, error in (
            ("missing_report_nonce", "%w[Content-Security-Policy Content-Security-Policy-Report-Only]", "%w[Content-Security-Policy]", b"built header/body nonce agreement changed"),
            ("missing_strict_dynamic", "sources = %w['strict-dynamic' 'wasm-unsafe-eval']", "sources = %w['wasm-unsafe-eval']", b"composition used a supplied unit CSP string"),
            ("wrong_body_nonce", "part.to_s.gsub(nonce_placeholder, nonce)", 'part.to_s.gsub(nonce_placeholder, "wrong")', b"wrong generated nonce"),
            ("missing_csp_warning", "@context.logger.warn(", "nil && @context.logger.warn(", b"composition lost actual logger effects"),
            ("unescaped_url", 'output << ERB::Util.html_escape(value_0)', 'output << value_0', b"ordinary URL expression was not escaped"),
            ("escaped_trusted_html", 'output << value_2.to_s', 'output << ERB::Util.html_escape(value_2.to_s)', b"trusted HTML was escaped as text"),
            ("omitted_modules", 'output << value_3.to_s', 'output << ""', b"module ordering/count changed"),
            ("lost_result_type", 'ActionView::HtmlFragment.new(output)', 'output', b"wrong final trusted fragment type"),
            ("html_escaped_raw_json", 'output << value\n', 'output << ERB::Util.html_escape(value)\n', b"raw JSON was HTML-escaped"),
            ("unsafe_script_closer", r"javascript.gsub!(%r{(</)}u, '\u003C/')", 'javascript', b"script closer escaped incorrectly"),
            ("double_preload_acquisition", 'value = preloaded_json\n', 'preloaded_json\nvalue = preloaded_json\n', b"preloaded data acquired incorrectly"),
            ("wrong_import_keys", 'real_url.sub(File.basename(real), File.basename(stable))', 'real_url', b"core stable import mapping lost"),
            ("escaped_importmap_json", 'output << imports.to_s', 'output << ERB::Util.html_escape(imports.to_s)', b"import-map JSON was escaped"),
            ("wrong_optional_stub", '"data:text/javascript,/* autogenerated missing optional plugin stub */const m=new Proxy({},{get:()=>null});export default new Proxy({},{get:()=>m});"', '"data:text/javascript,unit incorrect stub"', b"original optional plugin stub lost"),
        ):
            code = shared.read_text()
            self.assertIn(old, code)
            mutant = build / (name + ".rb")
            mutant.write_text(code.replace(old, new, 1))
            mutant_binary = build / name
            self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", mutant, "-o", mutant_binary])
            rejected = subprocess.run([str(mutant_binary), str(source), str(logs)], capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertIn(error, rejected.stderr, name)
            mutations[name] = rejected.returncode
        self.assertTrue(all(path.stat().st_mode & 0o777 == 0o600 for path in logs.iterdir()))
        policy_proof = json.loads((HERE / "compat/discourse/portable_csp_policy.json").read_text())
        self.assertEqual(policy_proof["runtime_sha256"], sha(csp_runtime.read_bytes()))
        self.assertEqual(policy_proof["candidate_sha256"], sha((HERE / "compat/discourse/lib/portable_csp_policy.rb").read_bytes()))
        proof = json.loads((HERE / "compat/discourse/portable_application_asset_fragment.json").read_text())
        self.assertEqual(proof["candidate_sha256"], sha(candidate.read_bytes()))
        self.assertEqual(proof["selected_span"]["text_sha256"], sha(fragment.read_bytes()))
        preload_proof = json.loads((HERE / "compat/discourse/portable_application_preload_fragment.json").read_text())
        self.assertEqual(preload_proof["selected_span"]["text_sha256"], sha(preload_fragment.read_bytes()))
        self.assertEqual(preload_proof["candidate_sha256"], sha((HERE / "compat/discourse/lib/portable_application_preload_fragment.rb").read_bytes()))
        importmap_proof = json.loads((HERE / "compat/discourse/portable_application_importmap_fragment.json").read_text())
        self.assertEqual(importmap_proof["candidate_sha256"], sha((HERE / "compat/discourse/lib/portable_application_importmap_fragment.rb").read_bytes()))
        evidence = {"status": "PASS_CONCRETE_LAYOUT_ASSET_PRELOAD_IMPORTMAP_FRAGMENTS_ONLY", "source_proof": proof,
                    "preload_source_proof": preload_proof, "importmap_source_proof": importmap_proof,
                    "built_policy_source_proof": policy_proof, "built_enforced_and_report_only_policy": True,
                    "real_owned_csp_warning_effects": True, "unit_preloads_not_site_settings_data": True, "unit_plugin_theme_vectors_not_activation": True,
                    "reference_json_encoder": "actual minimal ActionView context retains JSON gem Hash#to_json; not full Rails/Oj",
                    "original_shared_native_normalized_sha256": sha(expected), "matched_unit_contexts": 4,
                    "genuine_asset_files_read": len(records[4]["genuine_asset_reads"]),
                    "genuine_asset_bytes": sum(row[1] for row in records[4]["genuine_asset_reads"]),
                    "rendered_asset_urls_delivered": len(records[3]["delivered_assets"]),
                    "rendered_asset_response_bytes": sum(row["bytes"] for row in records[3]["delivered_assets"]),
                    "asset_server_compiler_patch": json.loads((build / "compiler-patch.json").read_text()),
                    "native_execve_count": 1, "native_connect_count": 0, "actual_randomness": True,
                    "unit_staff_values_not_authorization_proof": True, "real_file_backed_url_resolver": True,
                    "native_mutation_controls": mutations,
                    "original_html_accepted": False, "native_html_accepted": False,
                    "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS concrete original ERB/CRuby/native asset fragment (NOT a page): {build}")


if __name__ == "__main__":
    unittest.main()

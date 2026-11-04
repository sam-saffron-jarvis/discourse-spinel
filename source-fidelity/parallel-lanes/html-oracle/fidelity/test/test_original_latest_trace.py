from __future__ import annotations

import importlib.util
import json
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
spec = importlib.util.spec_from_file_location("trace_original_latest", HERE / "tools/trace_original_latest.py")
trace_tool = importlib.util.module_from_spec(spec)
assert spec.loader is not None
spec.loader.exec_module(trace_tool)


class OriginalLatestTraceHarnessTest(unittest.TestCase):
    def test_pnpm_lock_extraction_matches_line_anchored_ruby_split(self):
        pinned = (
            b"lockfileVersion: '9.0'\n"
            b"settings:\n  autoInstallPeers: true\n"
            b"---\n"
            b"importers:\n  .:\n    dependencies: {}\n"
            b"  embedded-text: |\n    not a delimiter ---\n"
            b"---\n"
            b"packages:\n  example@1.0.0: {}\n"
        )
        expected = b"packages:\n  example@1.0.0: {}\n"
        self.assertEqual(trace_tool.expected_installed_pnpm_lock(pinned), expected)
        embedded_delimiter = b"plain text ---\nthis is not a line-boundary delimiter"
        self.assertEqual(trace_tool.expected_installed_pnpm_lock(embedded_delimiter), embedded_delimiter)
        self.assertEqual(trace_tool.expected_installed_pnpm_lock(b"no separator\n"), b"no separator\n")

    def test_dependency_copy_preserves_only_symlinks_resolving_inside_archive(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            checkout = base / "checkout"
            archive = base / "private" / "discourse"
            modules = checkout / "node_modules"
            (modules / ".pnpm/pkg/node_modules/pkg").mkdir(parents=True)
            (modules / ".pnpm/pkg/node_modules/pkg/index.js").write_text("private dependency")
            (modules / ".pnpm/node_modules").mkdir(parents=True)
            (modules / ".pnpm/node_modules/pkg").symlink_to("../pkg/node_modules/pkg")
            (checkout / "frontend/workspace").mkdir(parents=True)
            (checkout / "frontend/workspace/index.js").write_text("tracked workspace")
            (archive / "frontend/workspace").mkdir(parents=True)
            (archive / "frontend/workspace/index.js").write_text("tracked workspace")
            (modules / ".pnpm/node_modules/workspace").symlink_to("../../../frontend/workspace")

            copied = archive / "node_modules"
            proof = trace_tool.copy_dependency_tree(modules, copied, checkout, archive)
            self.assertEqual(proof, {"symlink_count": 2, "symlink_targets_verified": 2})
            self.assertTrue((copied / ".pnpm/node_modules/pkg").is_symlink())
            self.assertEqual((copied / ".pnpm/node_modules/pkg/index.js").read_text(), "private dependency")
            self.assertTrue((copied / ".pnpm/node_modules/workspace").is_symlink())
            self.assertEqual((copied / ".pnpm/node_modules/workspace/index.js").read_text(), "tracked workspace")
            self.assertTrue((copied / ".pnpm/node_modules/workspace").resolve().is_relative_to(archive))

    def test_frontend_staging_flattens_links_into_private_archive_packages(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            checkout = base / "checkout"
            archive = base / "private/discourse"
            source_root_modules = checkout / "node_modules"
            source_workspace = checkout / "frontend/workspace"
            source_frontend_modules = checkout / "frontend/app/node_modules"
            (source_root_modules / ".pnpm/pkg/node_modules/pkg").mkdir(parents=True)
            (source_root_modules / ".pnpm/pkg/node_modules/pkg/index.js").write_text("root package")
            source_workspace.mkdir(parents=True)
            (source_workspace / "index.js").write_text("workspace package")
            (source_frontend_modules / "@scope").mkdir(parents=True)
            (source_frontend_modules / ".bin").mkdir()
            (source_frontend_modules / ".bin/tool").write_text("launcher")
            (source_frontend_modules / "pkg").symlink_to("../../../node_modules/.pnpm/pkg/node_modules/pkg")
            (source_frontend_modules / "@scope/workspace").symlink_to("../../../workspace")

            (archive / "node_modules/.pnpm/pkg/node_modules/pkg").mkdir(parents=True)
            (archive / "node_modules/.pnpm/pkg/node_modules/pkg/index.js").write_text("root package")
            (archive / "frontend/workspace").mkdir(parents=True)
            (archive / "frontend/workspace/index.js").write_text("workspace package")
            (archive / "frontend/app").mkdir(parents=True)

            result = trace_tool.stage_frontend_node_modules(
                source_frontend_modules, archive / "frontend/app/node_modules", checkout, archive
            )
            staged = archive / "frontend/app/node_modules"
            self.assertEqual(result, {"symlink_count": 2, "symlink_targets_verified": 2})
            self.assertEqual((staged / "pkg/index.js").read_text(), "root package")
            self.assertEqual((staged / "@scope/workspace/index.js").read_text(), "workspace package")
            self.assertEqual((staged / ".bin/tool").read_text(), "launcher")
            for link in staged.rglob("*"):
                if link.is_symlink():
                    self.assertTrue(link.resolve().is_relative_to(archive))

    def test_workspace_dependency_trees_are_copied_to_matching_archive_paths(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            checkout = base / "checkout"
            archive = base / "private/discourse"
            dependency = checkout / "frontend/pretty-text/node_modules/discourse"
            dependency.mkdir(parents=True)
            (dependency / "index.js").write_text("workspace source")
            (checkout / "frontend/discourse-markdown-it/node_modules").mkdir(parents=True)
            (checkout / "frontend/discourse-markdown-it/node_modules/pretty-text").symlink_to("../../pretty-text")
            (archive / "frontend/pretty-text").mkdir(parents=True, exist_ok=True)
            (archive / "frontend/pretty-text/index.js").write_text("workspace")

            copied = trace_tool.copy_workspace_dependency_trees(
                checkout, archive, {"frontend/discourse/node_modules"}
            )
            self.assertIn("frontend/discourse-markdown-it/node_modules", copied)
            link = archive / "frontend/discourse-markdown-it/node_modules/pretty-text"
            self.assertEqual(link.resolve(), archive / "frontend/pretty-text")

    def test_verified_frontend_build_reuse_checks_provenance_and_every_asset_hash(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            original_here = trace_tool.HERE
            trace_tool.HERE = base
            try:
                build_root = base / "build"
                artifact = build_root / "prior"
                output = build_root / "next"
                artifact.mkdir(parents=True)
                output.mkdir()
                discourse = output / "discourse"
                app = discourse / "frontend/discourse"
                (app / "lib").mkdir(parents=True)
                (app / "package.json").write_text("{}")
                (app / "rolldown.config.mjs").write_text("config")
                (app / "discourse.js").write_text("entry")
                (app / "lib/source.mjs").write_text("source")
                (discourse / "pnpm-lock.yaml").write_bytes(b"header\n---\ninstalled-lock\n")

                dist = artifact / "discourse/frontend/discourse/dist"
                (dist / "manifest").mkdir(parents=True)
                (dist / "manifest/manifest.json").write_text('{"entrypoints":{}}')
                (dist / "assets/js/core.js").parent.mkdir(parents=True)
                (dist / "assets/js/core.js").write_text("real built output")
                outputs, total = trace_tool.verified_frontend_dist_hashes(dist)
                manifest_hash = outputs["manifest/manifest.json"]
                installed_hash = trace_tool.sha(trace_tool.expected_installed_pnpm_lock(
                    (discourse / "pnpm-lock.yaml").read_bytes()
                ))
                inputs = {
                    "source_revision": trace_tool.PIN,
                    "source_files_sha256": trace_tool.frontend_build_source_hashes(discourse),
                    "pinned_pnpm_lock_sha256": trace_tool.sha((discourse / "pnpm-lock.yaml").read_bytes()),
                    "installed_root_pnpm_lock_sha256": installed_hash,
                }
                (artifact / "state.json").write_text(json.dumps({
                    "status": "traced", "source_revision": trace_tool.PIN,
                    "source_checkout_not_modified": True,
                }))
                (artifact / "frontend-asset-build.json").write_text(json.dumps({
                    "status": "built", "inputs": inputs, "manifest_sha256": manifest_hash,
                    "output_file_count": len(outputs), "output_bytes": total,
                    "output_files_sha256": outputs,
                }))

                reused = trace_tool.reuse_verified_frontend_build(artifact, discourse, output)
                self.assertEqual(reused["status"], "reused_verified")
                self.assertEqual(reused["manifest_sha256"], manifest_hash)
                self.assertEqual(trace_tool.verified_frontend_dist_hashes(app / "dist"), (outputs, total))

                (dist / "assets/js/core.js").write_text("tampered")
                next_output = build_root / "next-tampered"
                next_output.mkdir()
                next_discourse = next_output / "discourse"
                (next_discourse / "frontend/discourse").mkdir(parents=True)
                (next_discourse / "frontend/discourse/package.json").write_text("{}")
                (next_discourse / "frontend/discourse/rolldown.config.mjs").write_text("config")
                (next_discourse / "frontend/discourse/discourse.js").write_text("entry")
                (next_discourse / "frontend/discourse/lib").mkdir()
                (next_discourse / "frontend/discourse/lib/source.mjs").write_text("source")
                (next_discourse / "pnpm-lock.yaml").write_bytes(b"header\n---\ninstalled-lock\n")
                with self.assertRaisesRegex(RuntimeError, "output file/hash inventory"):
                    trace_tool.reuse_verified_frontend_build(artifact, next_discourse, next_output)
            finally:
                trace_tool.HERE = original_here

    def test_dependency_copy_rejects_symlink_outside_original_checkout(self):
        with tempfile.TemporaryDirectory() as temporary:
            base = Path(temporary)
            checkout = base / "checkout"
            archive = base / "private/discourse"
            modules = checkout / "node_modules"
            outside = base / "outside"
            modules.mkdir(parents=True)
            archive.mkdir(parents=True)
            outside.mkdir()
            (modules / "escape").symlink_to("../../outside", target_is_directory=True)
            with self.assertRaisesRegex(RuntimeError, "escapes original checkout"):
                trace_tool.copy_dependency_tree(modules, archive / "node_modules", checkout, archive)
            self.assertFalse((archive / "node_modules").exists())

    def test_source_pin_and_real_declaration_trace_inputs(self):
        self.assertEqual(trace_tool.PIN, "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8")
        for expected in (
            "app/models/site_setting.rb", "lib/site_setting_extension.rb",
            "lib/site_settings/yaml_loader.rb", "lib/application_layout_preloader.rb",
            "app/controllers/list_controller.rb", "lib/topic_list_responder.rb",
            "app/serializers/topic_list_serializer.rb", "app/serializers/topic_list_item_serializer.rb",
        ):
            self.assertIn(expected, trace_tool.MATERIALIZED_LOCK_FILES)

    def test_thread_phase_is_not_inherited_by_concurrent_worker_and_exception_is_sanitized(self):
        code = r'''require "json"
require "oracle_observation"
require "tmpdir"
FidelityOracleObservation.begin_request(phase: "request_html", request_id: "r1", path: "/latest")
main = FidelityOracleObservation.context
ENV["FIDELITY_ORACLE_PHASE"] = "request_page1"
worker = Thread.new { FidelityOracleObservation.context }.value
root = Dir.mktmpdir("fidelity-exception-")
begin
  eval('begin; raise "private cause"; rescue => cause; raise "private fatal"; end',
       TOPLEVEL_BINDING, "#{root}/app/models/fatal_probe.rb", 27)
rescue => error
  safe = FidelityOracleObservation.safe_exception(error, root: root)
end
FidelityOracleObservation.end_request("r1")
puts JSON.generate(main: main, worker: worker, exception: safe)
'''
        result = subprocess.run(
            ["ruby", "-I", str(HERE / "tools"), "-e", code],
            check=True, capture_output=True, text=True,
        )
        record = json.loads(result.stdout)
        self.assertEqual(record["main"]["thread_role"], "request")
        self.assertEqual(record["main"]["phase"], "request_html")
        self.assertEqual(record["worker"]["thread_role"], "concurrent")
        self.assertEqual(record["worker"]["phase"], "concurrent")
        self.assertEqual(record["worker"]["active_request_id"], "r1")
        exception = record["exception"]
        self.assertEqual(exception["error_class"], "RuntimeError")
        self.assertEqual(exception["cause_chain"], ["RuntimeError", "RuntimeError"])
        self.assertTrue(any(frame["source"] == "app/models/fatal_probe.rb" and frame["line"] == 27
                            for frame in exception["original_app_backtrace"]))
        self.assertNotIn("private cause", result.stdout)
        self.assertNotIn("private fatal", result.stdout)

    def test_runner_has_explicit_non_overwriting_paths_and_private_endpoints(self):
        source = (HERE / "tools/trace_original_latest.py").read_text()
        consumer = (HERE / "tools/original_latest_trace_consumer.rb").read_text()
        self.assertIn('parser.add_argument("--root", required=True', source)
        self.assertIn('parser.add_argument("--output", required=True', source)
        self.assertIn('if output.exists():', source)
        self.assertIn('if output == root or root in output.parents', source)
        self.assertIn('"PGPORT": "5499"', source)
        self.assertIn("default_transaction_read_only=on", source)
        self.assertNotIn("copied_not_linked", source)
        self.assertIn("/latest.json?page=0", consumer)
        self.assertIn("/latest.json?page=1", consumer)
        self.assertIn("/latest", consumer)
        self.assertIn("deliberate_cold_getter", consumer)
        self.assertNotIn("HTTP_COOKIE", consumer)
        self.assertNotIn("Set-Cookie", consumer)
        self.assertIn("ForbiddenExternalEffect", consumer)
        self.assertIn("SOURCE_LINE_WATCH", consumer)
        self.assertIn('TracePoint.new(:call, :line, :raise)', consumer)
        self.assertIn('Rack::MockRequest.new(wrapped_app).get', consumer)
        self.assertIn("action_dispatch.exception action_dispatch.original_exception", consumer)
        self.assertIn("safe_exception(exception, root: ROOT)", consumer)
        self.assertIn('request_exceptions', consumer)
        self.assertIn('phase: "concurrent"', (HERE / "tools/oracle_observation.rb").read_text())
        self.assertIn('original_callers: root ? FidelityOracleObservation.original_app_callers',
                      (HERE / "tools/oracle_isolation.rb").read_text())
        self.assertIn('"lib/site_settings/yaml_loader.rb" => [8, 9, 10, 11, 18, 20, 23]', consumer)
        guard = (HERE / "tools/oracle_isolation.rb").read_text()
        self.assertIn("known_worker = (@vips_workers || {})[pid].equal?(worker)", guard)
        self.assertIn('known_worker || command.include?("#{root}/script/discourse_vips_worker")', guard)
        self.assertIn("previously_proven: known_worker", guard)

    def test_untrusted_or_secret_response_values_are_not_written(self):
        consumer = (HERE / "tools/original_latest_trace_consumer.rb").read_text()
        self.assertIn("response.body.bytesize", consumer)
        self.assertIn("JSON.parse(response.body)", consumer)
        self.assertIn("info[:first_topic_keys]", consumer)
        self.assertNotIn("response.body,", consumer)
        self.assertNotIn("getter_value:", consumer)
        self.assertNotIn("headers.to_h", consumer)


if __name__ == "__main__":
    unittest.main()

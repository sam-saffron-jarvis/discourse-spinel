"""Actual CSP Default/Builder/ActionDispatch policy construction in explicit unit contexts."""
import hashlib
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class CspPolicyTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT, timeout=120):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=timeout,
                                env={**os.environ, "RAILS_ENV": "development"})
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_source_default_builder_real_serializer_and_logger(self):
        build = Path(tempfile.mkdtemp(prefix="csp-policy-", dir=HERE / "build"))
        original_methods = build / "original-policy.rb"
        self.command(["ruby", HERE / "tools/generate_csp_policy.rb", original_methods])
        assets_context = (HERE / "test/asset_url_unit_context.rb").read_bytes().split(b"class UnitUrlRequest", 1)[0]
        context = assets_context + b"\n" + (HERE / "test/csp_policy_unit_context.rb").read_bytes()
        matrix = (HERE / "test/csp_policy_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes((HERE / "test/csp_policy_original_backend.rb").read_bytes() + b'\ndef unit_set_source(policy, name, sources)\npolicy.public_send(name.gsub("-", "_"), *sources)\nend\n' + original_methods.read_bytes() + b"\n" + context + b"\n" + matrix)
        runtime = ROOT / "roundhouse/runtime/ruby/action_dispatch/content_security_policy.rb"
        candidate = HERE / "compat/discourse/lib/portable_csp_policy.rb"
        shared = build / "shared.rb"
        shared.write_bytes(runtime.read_bytes() + b"\n" + candidate.read_bytes() + b"\n" + context + b'''
def unit_set_source(policy, name, sources)
  policy.set_source_directive(name, sources)
end
''' + (HERE / "test/csp_policy_shared_backend.rb").read_bytes() + matrix)
        shared.with_suffix(".rbs").write_bytes(runtime.with_suffix(".rbs").read_bytes())
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        runs = {}
        for name, argv, cwd in (
            ("original", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], ROOT / "discourse"),
            ("shared", ["ruby", "--enable-frozen-string-literal", shared], ROOT),
            ("native", [binary], ROOT),
        ):
            logs = build / (name + "-owned-logs")
            logs.mkdir(mode=0o700)
            runs[name] = self.command([*argv, logs], cwd=cwd)
            self.assertTrue(all(path.stat().st_mode & 0o777 == 0o600 for path in logs.iterdir()))
        self.assertEqual(runs["original"], runs["shared"])
        self.assertEqual(runs["original"], runs["native"])
        trace = build / "native.trace"
        traced_logs = build / "traced-owned-logs"
        traced_logs.mkdir(mode=0o700)
        self.assertEqual(runs["original"], self.command(["strace", "-f", "-e", "trace=execve,connect,openat,write,close", "-o", trace, binary, traced_logs]))
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        self.assertIn(".log", trace.read_text())
        mutations = {}
        for name, old, new, error in (
            ("report_upgrade", "&& !report_only", "", b"upgrade flag semantics changed"),
            ("strict_dynamic_filter", "s == \"'unsafe-inline'\" || s == \"'self'\" || !s.start_with?(\"'\")", "false", b"strict-dynamic source filtering failed"),
            ("none_removal", "@directives[directive].delete(:none)", "nil", b"none symbol not removed"),
            ("relative_source", '\"#{@base_url}#{source}\"', "source", b"relative extension normalization lost"),
            ("missing_warning", "@context.logger.warn(", "nil && @context.logger.warn(", b"real warning effects missing"),
            ("frame_hosts", '@context.host_store.pluck(:host)', '[]', b"default frame host acquisition omitted/broadened"),
            ("source_mapping", "'#{source}'", "#{source}", b"serializer source mapping/deletion/report semantics changed"),
            ("report_mapping", 'self.[]=(name, [source.to_s])', 'self.[]=(name, [map_source(source)])', b"serializer source mapping/deletion/report semantics changed"),
            ("serializer_validation", 'validate_source(name, sources[index])', 'nil', b"invalid default directive admitted"),
        ):
            code = shared.read_text()
            self.assertIn(old, code, name)
            mutant = build / (name + ".rb")
            mutant.write_text(code.replace(old, new, 1))
            mutant_binary = build / name
            self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", mutant, "-o", mutant_binary])
            logs = build / (name + "-logs")
            logs.mkdir(mode=0o700)
            rejected = subprocess.run([str(mutant_binary), str(logs)], capture_output=True, timeout=30)
            self.assertNotEqual(rejected.returncode, 0, name)
            self.assertIn(error, rejected.stderr, name)
            mutations[name] = {"returncode": rejected.returncode, "stderr": rejected.stderr.decode(errors="replace")}
        records = [json.loads(line) for line in runs["original"].splitlines()[:-1]]
        self.assertEqual(len(records), 5)
        proof = json.loads((HERE / "compat/discourse/portable_csp_policy.json").read_text())
        self.assertEqual(proof["runtime_sha256"], hashlib.sha256(runtime.read_bytes()).hexdigest())
        self.assertEqual(proof["candidate_sha256"], hashlib.sha256(candidate.read_bytes()).hexdigest())
        evidence = {"status": "PASS_UNIT_SOURCE_DEFAULT_BUILDER_ACTIONDISPATCH_CSP", "source_proof": proof,
                    "original_shared_native_sha256": hashlib.sha256(runs["original"]).hexdigest(),
                    "unit_contexts": [row["name"] for row in records[:4]], "real_owned_logger_effects": True, "native_mutation_controls": mutations,
                    "native_execve_count": 1, "native_connect_count": 0,
                    "embeddable_host_fixture_not_real_query": True, "theme_extension_baking_accepted": False,
                    "original_html_accepted": False, "native_html_accepted": False,
                    "browser_accepted": False, "page_accepted": False}
        (build / "evidence.json").write_text(json.dumps(evidence, indent=2) + "\n")
        print(f"PASS original Default/Builder/ActionDispatch vs shared/native CSP and real warning effects: {build}")


if __name__ == "__main__":
    unittest.main()

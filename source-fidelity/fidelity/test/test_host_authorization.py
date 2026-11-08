import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class HostAuthorizationTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        env = {**os.environ, "RAILS_ENV": "development"}
        result = subprocess.run([str(value) for value in argv], cwd=cwd, env=env, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_real_original_shared_native_host_permissions_and_scope(self):
        build = Path(tempfile.mkdtemp(prefix="host-authorization-", dir=HERE / "build"))
        candidate = HERE / "compat/framework/portable_host_authorization.rb"
        extractor = r'''require "prism"
owner = Prism.parse_file(ARGV[0]).value.statements.body.grep(Prism::ModuleNode).find { |node| node.constant_path.slice == "PortableHostAuthorizationDeclarations" }
raise "source host declarations missing" unless owner
puts owner.slice
'''
        declarations = self.command(["ruby", "-e", extractor, candidate])
        matrix = (HERE / "test/host_authorization_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes(b'require "action_dispatch"\nrequire "action_view"\nrequire "fast_blank"\n' + declarations + b"\n" + matrix)
        shared = build / "shared.rb"
        shared.write_bytes((HERE / "compat/framework/portable_profiler_request.rb").read_bytes() + b"\n" +
            (HERE / "compat/framework/portable_json_response_middleware.rb").read_bytes() + b"\n" + candidate.read_bytes() + b"\n" + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", "--int-overflow=promote", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        trace = build / "native.trace"
        self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary])
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        self.assertIn(b"omitted/live-config controls", expected)


if __name__ == "__main__":
    unittest.main()

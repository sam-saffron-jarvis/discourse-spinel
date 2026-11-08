from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class JsonProfileMiddlewareTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_genuine_original_shared_native_short_circuit_paths_and_refusals(self):
        build = Path(tempfile.mkdtemp(prefix="json-profile-middleware-", dir=HERE / "build"))
        matrix = (HERE / "test/json_profile_middleware_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes(b'''require "action_dispatch"
require "active_support/core_ext/module/delegation"
require "active_support/core_ext/object/blank"
require "fast_blank"
require "omniauth"
require "rack/head"
require "rack/method_override"
$LOAD_PATH.unshift(ARGV.fetch(0))
require "middleware/missing_avatars"
require "middleware/omniauth_bypass_middleware"
require "content_security_policy/middleware"
require "middleware/crawler_hooks"
''' + matrix)
        shared = build / "shared.rb"
        shared.write_bytes((HERE / "compat/framework/portable_profiler_request.rb").read_bytes() + b"\n" +
            (HERE / "compat/framework/portable_json_response_middleware.rb").read_bytes() + b"\n" +
            (HERE / "compat/framework/portable_json_profile_middleware.rb").read_bytes() + b"\n" + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original, ROOT / "discourse/lib"], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        trace = build / "native.trace"
        self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary])
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        self.assertIn(b"executable excluded-profile/omission controls", expected)


if __name__ == "__main__":
    unittest.main()

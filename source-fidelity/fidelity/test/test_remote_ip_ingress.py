import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class RemoteIpIngressTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_direct_peer_and_admission(self):
        build = Path(tempfile.mkdtemp(prefix="remote-ip-ingress-", dir=HERE / "build"))
        ingress = (HERE / "compat/framework/portable_json_ingress.rb").read_bytes()
        matrix = (HERE / "test/remote_ip_ingress_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes(b'require "action_dispatch"\n' + ingress + b"\n" + matrix)
        shared = build / "shared.rb"
        shared.write_bytes((HERE / "compat/framework/portable_profiler_request.rb").read_bytes() + b"\n" +
            (HERE / "compat/framework/portable_remote_ip.rb").read_bytes() + b"\n" + ingress + b"\n" + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", "--load-model=graph", "--int-overflow=promote", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        trace = build / "native.trace"
        self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary])
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        self.assertIn(b"singleton-range equivalence", expected)


if __name__ == "__main__":
    unittest.main()

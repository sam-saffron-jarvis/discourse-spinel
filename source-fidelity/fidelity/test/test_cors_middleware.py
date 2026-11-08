from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class CorsMiddlewareTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_actual_header_algorithm(self):
        build = Path(tempfile.mkdtemp(prefix="cors-middleware-", dir=HERE / "build"))
        extractor = r'''require "prism"
source = Prism.parse_file(ARGV[0]).value.statements.body.grep(Prism::ClassNode).first
raise "original CORS changed" unless source.constant_path.slice == "Discourse::Cors"
puts source.slice
'''
        original_source = self.command(["ruby", "-e", extractor, ROOT / "discourse/config/initializers/008-rack-cors.rb"])
        matrix = (HERE / "test/cors_middleware_matrix.rb").read_bytes()
        original = build / "original.rb"
        # Namespace-only original declaration, not a model/settings/security API.
        original.write_bytes(b'require "active_support/core_ext/enumerable"\nmodule Discourse; end\n' + original_source + b"\n" + matrix)
        shared = build / "shared.rb"
        shared.write_bytes(b'module Discourse; end\n' + (HERE / "compat/framework/portable_cors_middleware.rb").read_bytes() + b"\n" + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        self.assertIn(b"omitted/wrong controls", expected)


if __name__ == "__main__":
    unittest.main()

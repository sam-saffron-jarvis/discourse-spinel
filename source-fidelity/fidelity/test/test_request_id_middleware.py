import json
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class RequestIdMiddlewareTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_middleware_scope_and_effects(self):
        build = Path(tempfile.mkdtemp(prefix="request-id-middleware-", dir=HERE / "build"))
        extractor = r'''require "prism"
owner = Prism.parse_file(ARGV[0]).value.statements.body.grep(Prism::ModuleNode).first
node = owner.body.body.grep(Prism::ClassNode).find { |item| item.constant_path.slice == "RequestIdMiddleware" }
raise "actual runtime middleware missing" unless node
puts "module ActionDispatch\n#{node.slice}\nend"
'''
        middleware = self.command(["ruby", "-e", extractor, ROOT / "roundhouse/runtime/spinel/inprocess_controller.rb"])
        matrix = (HERE / "test/request_id_middleware_matrix.rb").read_bytes()
        framework = (ROOT / "roundhouse/runtime/ruby/action_dispatch/request_id.rb").read_bytes()
        for context in ("rails", "discourse"):
            original = build / (context + "-original.rb")
            original_prefix = b'require "action_dispatch"\n'
            shared_prefix = b'require "securerandom"\n' + framework + b"\n" + middleware
            if context == "discourse":
                original_prefix += b'require "fast_blank"\nFAST_BLANK_CONTEXT = true\n'
                shared_prefix += b"\n" + (HERE / "compat/framework/portable_json_response_middleware.rb").read_bytes()
                shared_prefix += b"\n" + (HERE / "compat/framework/portable_discourse_request_id_middleware.rb").read_bytes()
                shared_prefix += b"\nFAST_BLANK_CONTEXT = true\nRequestIdMiddlewareUnderTest = PortableDiscourseRequestIdMiddleware\n"
            else:
                original_prefix += b"FAST_BLANK_CONTEXT = false\n"
                shared_prefix += b"\nFAST_BLANK_CONTEXT = false\nRequestIdMiddlewareUnderTest = ActionDispatch::RequestIdMiddleware\n"
            original.write_bytes(original_prefix + b'RequestIdMiddlewareUnderTest = ActionDispatch::RequestId\n' + matrix)
            shared = build / (context + "-shared.rb")
            shared.write_bytes(shared_prefix + matrix)
            binary = build / (context + "-probe")
            self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", shared, "-o", binary])
            expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], cwd=ROOT / "discourse")
            self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
            self.assertEqual(expected, self.command([binary]))
            self.assertIn(b"omitted-consumer controls", expected)



if __name__ == "__main__":
    unittest.main()

import json
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class ResponseMiddlewareTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=90)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_reproducible_original_source_and_native_response_effects(self):
        manifest_path = HERE / "progressive/stage4_request/PROFILER_SOURCE_MANIFEST.json"
        before = manifest_path.read_bytes()
        manifest = json.loads(before)["response_middleware"]
        candidate = HERE / manifest["candidate"]
        candidate_bytes = candidate.read_bytes()
        self.command(["ruby", HERE / "tools/generate_request_profiler.rb"])
        self.assertEqual(before, manifest_path.read_bytes())
        self.assertEqual(candidate_bytes, candidate.read_bytes())
        self.assertFalse(manifest["full_stack_accepted"])
        self.assertFalse(manifest["observed_payloads_as_inputs"])
        # The reference caller loads complete original middleware source.
        # Only the two original declarations are projected: no invented APIs,
        # settings, permission provider, callback or replacement algorithm.
        extractor = r'''require "prism"
require "active_support/core_ext/object/blank"
require "fast_blank"
require "securerandom"
def declaration(path, name)
  found = nil
  visit = lambda do |node|
    found = node if node.is_a?(Prism::ConstantWriteNode) && node.name == name
    node.compact_child_nodes.each { |child| visit.call(child) }
  end
  visit.call(Prism.parse_file(path).value)
  raise "missing actual declaration" unless found
  found.slice
end
root = ARGV.fetch(0)
puts 'require "active_support/core_ext/object/blank"'
puts 'require "fast_blank"'
puts 'require "securerandom"'
puts "module MarkdownEndpoint; class RequestConstraint; #{declaration(root + '/lib/markdown_endpoint/request_constraint.rb', :VARY_ACCEPT_ENV_KEY)}; end; end"
puts "module Middleware; class RequestTracker; #{declaration(root + '/lib/middleware/request_tracker.rb', :MAX_SESSION_ID_LENGTH)}; end; end"
%w[lib/markdown_endpoint/vary_middleware.rb lib/middleware/track_view_session_id_injector.rb lib/middleware/csp_script_nonce_injector.rb].each { |path| puts File.binread(root + '/' + path) }
'''
        reference = self.command(["bundle", "exec", "ruby", "-e", extractor, ROOT / "discourse"], cwd=ROOT / "discourse")
        build = Path(tempfile.mkdtemp(prefix="response-middleware-", dir=HERE / "build"))
        matrix = (HERE / "test/response_middleware_matrix.rb").read_bytes()
        original = build / "original.rb"
        original.write_bytes(reference + b"\n" + matrix)
        shared = build / "shared.rb"
        profile_guards = b'''
begin
  PortableResponseMiddlewareDeclarations.blank_header?(123)
  raise "non-string response header was accepted"
rescue ArgumentError => error
  raise unless error.message == "unsupported non-string response header profile"
end
'''
        shared.write_bytes(candidate_bytes + b"\n" + profile_guards + matrix)
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--cc=clang", "--jobs=4", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", "--enable-frozen-string-literal", original], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", "--enable-frozen-string-literal", shared]))
        self.assertEqual(expected, self.command([binary]))
        self.assertIn(b"omitted and reversed-order negatives", expected)


if __name__ == "__main__":
    unittest.main()

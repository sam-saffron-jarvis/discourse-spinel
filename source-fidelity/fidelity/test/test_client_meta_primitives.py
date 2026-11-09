"""UNIT-only actual meta escaping and ERB URI primitives; no services or page claim."""
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
ROOT = HERE.parent


class ClientMetaPrimitiveTests(unittest.TestCase):
    def command(self, argv, cwd=ROOT):
        result = subprocess.run([str(value) for value in argv], cwd=cwd, capture_output=True, timeout=120)
        self.assertEqual(result.returncode, 0, result.stderr.decode(errors="replace"))
        return result.stdout

    def test_original_shared_native_meta_and_component_uri(self):
        build = Path(tempfile.mkdtemp(prefix="client-meta-primitives-", dir=HERE / "build"))
        extractor = '''require "prism"
name = ARGV.fetch(1).to_sym
nodes = []
visit = lambda do |node|
  nodes << node if node.is_a?(Prism::DefNode) && node.name == name
  node.compact_child_nodes.each { |child| visit.call(child) }
end
visit.call(Prism.parse_file(ARGV.fetch(0)).value)
raise "ambiguous primitive method" unless nodes.size == 1
puts nodes.first.slice
'''
        serialize = self.command(["ruby", "-e", extractor, HERE / "test/client_meta_context.rb", "serialize_meta"])
        uri = self.command(["ruby", "-e", extractor, HERE / "test/body_layout_context.rb", "u"])
        # Explicit UNIT vectors, not effective setting values, DB rows, or cache inputs.
        matrix = b'''vectors = [
  {cdn: nil, is_staff: false, user_color_scheme_id: -1, environment: "development"},
  {cdn: "<>&\\\"'\\n\\r\\t", svg_icon_list: ["a\\\"b", "<svg>&", "caf\xc3\xa9", "\\u2028\\u2029"]},
  {environment: "a+b c/~?\\\"\xc3\xa9", svg_icon_list: [], is_staff: true},
]
vectors.each do |data|
  before = JSON.generate(data)
  html = unit_meta(data)
  raise "UNIT meta input mutated" unless JSON.generate(data) == before
  puts JSON.generate({html: html.to_s, input_unchanged: true})
end
["a b+c/~?", "<>&\\\"'", "caf\xc3\xa9\\t\\n\\u2028"].each do |text|
  puts JSON.generate({uri: unit_uri(text)})
end
'''
        original = build / "original.rb"
        # Match the pinned application's explicit Rails load_defaults profile,
        # not unconfigured ActiveSupport's legacy JS-separator default.
        application = self.command(["git", "-C", ROOT / "discourse", "show", "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8:config/application.rb"])
        self.assertEqual(application, (ROOT / "discourse/config/application.rb").read_bytes())
        self.assertIn(b'config.load_defaults 8.1', application)
        original.write_bytes(b'''require "json"
require "erb"
require "action_view"
require "active_support/core_ext/object/json"
require "rails"
require "rails/application/configuration"
require "pathname"
unit_config = Rails::Application::Configuration.new(Pathname.pwd)
unit_config.load_defaults(8.1)
ActiveSupport.escape_js_separators_in_json = unit_config.active_support.escape_js_separators_in_json
class UnitOriginalMeta
  include ActionView::Helpers::TagHelper
end
def unit_meta(data)
  value = UnitOriginalMeta.new.tag.meta(id: 'data-discourse-setup', data: data)
  raise 'UNIT original meta lost trusted type' unless value.html_safe?
  value
end
def unit_uri(text); ERB::Util.url_encode(text); end
''' + matrix)
        shared = build / "shared.rb"
        def relative(path):
            return json.dumps(os.path.relpath(path, build))
        shared.write_bytes((f'''require "json"
require "cgi"
require "base64"
require_relative {relative(ROOT / 'roundhouse/runtime/ruby/action_view/view_helpers.rb')}
require_relative {relative(ROOT / 'roundhouse/runtime/ruby/json_builder.rb')}
# UNIT admitted key subset, not a settings/data replacement.
module ClientMetaDeclarations
  KEYS = [:cdn, :is_staff, :user_color_scheme_id, :environment, :svg_icon_list]
end
module ClientMetaRead
'''.encode() + serialize + b"\nend\nmodule UnitCandidateURI\n" + uri + b'''\nend
class UnitCandidateMeta
  include UnitCandidateURI
end
def unit_meta(data); ClientMetaRead.serialize_meta('data-discourse-setup', data); end
def unit_uri(text); UnitCandidateMeta.new.u(text); end
''' + matrix + b'''
# Candidate-only admitted-profile rejection controls, not generic ActionView claims.
def unit_candidate_refusal(id, data, message)
  begin
    ClientMetaRead.serialize_meta(id, data)
  rescue ArgumentError, TypeError => error
    raise "UNIT unexpected refusal diagnostic" unless error.message == message
    puts JSON.generate({refused: true, expected_error: message})
    return
  end
  raise "UNIT unsupported meta profile admitted"
end
if ARGV.first == '--guards'
  unit_candidate_refusal('wrong-id', {}, 'unacquired meta id/attributes profile')
  unit_candidate_refusal('data-discourse-setup', {unacquired_key: 'x'}, 'unacquired client meta key')
  unit_candidate_refusal('data-discourse-setup', {svg_icon_list: [nil]}, 'unacquired client meta data value type')
  unit_candidate_refusal('data-discourse-setup', {cdn: {nested: 'x'}}, 'unacquired client meta data value type')
  unit_candidate_refusal('data-discourse-setup', [], 'unacquired meta id/attributes profile')
end
'''))
        binary = build / "probe"
        self.command([ROOT / "spinel/spinel", "--jobs=4", "--cc=clang", "--load-model=graph", "-O", "0", shared, "-o", binary])
        expected = self.command(["bundle", "exec", "ruby", original], cwd=ROOT / "discourse")
        self.assertEqual(expected, self.command(["ruby", shared]))
        self.assertEqual(expected, self.command([binary]))
        trace = build / "native.trace"
        self.assertEqual(expected, self.command(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary]))
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())
        records = [json.loads(line) for line in expected.splitlines()]
        self.assertEqual(len(records), 6)
        self.assertIn("%20", records[3]["uri"])
        self.assertIn("%C3%A9", records[5]["uri"])
        guarded = self.command([binary, "--guards"])
        self.assertEqual(guarded, self.command(["ruby", shared, "--guards"]))
        guard_records = [json.loads(line) for line in guarded.splitlines()]
        self.assertEqual(guard_records[:6], records)
        self.assertEqual(len(guard_records), 11)
        self.assertTrue(all(row["refused"] for row in guard_records[6:]))
        (build / "evidence.json").write_text(json.dumps({"status": "PASS_UNIT_ACTUAL_META_AND_ERB_URI_PRIMITIVES", "rails_load_defaults": "8.1 from unchanged pinned app", "records": records, "candidate_admission_controls": guard_records[6:], "native_execve": 1, "native_connect": 0, "live_inputs_used": False, "page_accepted": False}, indent=2) + "\n")
        print(f"PASS UNIT actual meta/URI original/shared/native: {build}")


if __name__ == "__main__":
    unittest.main()

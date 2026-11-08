import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

HERE = Path(__file__).resolve().parents[1]
sys.path.insert(0, str(HERE / "tools"))
from execute_latest_json_request import validate_request_trace
from probe_latest_json_rails import comparable
from verify import equal_records


class LatestJsonRequestTests(unittest.TestCase):
    def test_source_generation_is_reproducible_and_keeps_full_original_controllers(self):
        report_path = HERE / "progressive/stage4_request/MANIFEST.json"
        report = json.loads(report_path.read_text())
        paths = [report_path, HERE / "SOURCE_LOCK.json"]
        paths += [HERE / "compat/discourse" / name for name in report["candidate_source_sha256"]]
        before = {str(path): path.read_bytes() for path in paths}
        result = subprocess.run(["ruby", HERE / "tools/generate_latest_json_request.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(before, {str(path): path.read_bytes() for path in paths})
        for flag in ("json_request_accepted", "full_query_accepted", "page_accepted", "effective_values_or_observed_payloads_used"):
            self.assertFalse(report[flag])
        controller = (HERE / "compat/discourse/app/controllers/list_controller.rb").read_text()
        original = (HERE / "source/discourse/app/controllers/list_controller.rb").read_text()
        self.assertEqual(controller.replace('require_relative "../../lib/portable_latest_json_action"\n\n', '', 1)
                         .replace("\n  prepend PortableLatestJsonAction", '', 1), original)
        action = (HERE / "compat/discourse/lib/portable_latest_json_action.rb").read_text()
        for text in ("return super unless request.format.json?", "TopicQuery.new(current_user, list_opts).list_latest",
                     "TopicListSerializer.new(list, scope: guardian).as_json", "construct_latest_json_url_with(:next, list_opts)",
                     "construct_latest_json_url_with(:prev, list_opts)", "discourse_expires_in 1.minute"):
            self.assertIn(text, action)
        self.assertNotIn("SELECT", action)
        self.assertNotIn('"topic_list" =>', action)

    def test_live_login_policy_dsl_matches_original_on_cruby_and_native(self):
        build = Path(tempfile.mkdtemp(prefix="login-policy-", dir=HERE / "build"))
        source = build / "probe.rb"
        extractor = r'''require "prism"
# Bundle the exact shared bytes: no absolute require-path behavior is under test.
puts File.binread(ARGV[2])
[ARGV[0], ARGV[1]].each_with_index do |file, index|
  owner = Prism.parse_file(file).value.statements.body.grep(Prism::ClassNode).first
  methods = owner.body.body.grep(Prism::DefNode).select { |node| [:requires_login, :requires_login_arg].include?(node.name) }
  raise "login DSL source changed" unless methods.length == 2
  prefix = index == 0 ? "ReferencePolicy" : "SharedPolicy"
  puts "class #{prefix}Parent\n#{methods.map(&:slice).join("\n")}\nend"
  puts "class #{prefix}Child < #{prefix}Parent; end"
  puts "class #{prefix}Sibling < #{prefix}Parent; end"
end
'''
        result = subprocess.run(["ruby", "-e", extractor,
            HERE / "source/discourse/app/controllers/application_controller.rb",
            HERE / "compat/discourse/app/controllers/application_controller.rb",
            HERE / "compat/discourse/lib/portable_controller_login_policy.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        source.write_text(result.stdout + (HERE / "test/controller_login_policy_matrix.rb").read_text())
        binary = build / "probe"
        result = subprocess.run([HERE.parent / "spinel/spinel", "--cc=clang", "--jobs=4", source, "-o", binary], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        outputs = []
        for argv in (["ruby", source], [binary]):
            result = subprocess.run(argv, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs.append(result.stdout)
        self.assertEqual(outputs[0], outputs[1])
        self.assertIn("PASS original/shared per-class writable", outputs[0])

    def test_actor_refresh_uses_real_concrete_session_and_cookie_types(self):
        from probe_latest_json_request import LatestJsonRequestRun
        run = LatestJsonRequestRun()
        try:
            run.provenance()
            run.generate()
            source = run.path / "session-unit.rb"
            source.write_bytes((HERE / "test/latest_request_session.rb").read_bytes())
            binary = run.path / "session-unit"
            result = subprocess.run([HERE.parent / "spinel/spinel", "--cc=clang", "--jobs=4", "--rbs", run.path / "emitted",
                                     source, "-o", binary], capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs = []
            for argv in (["ruby", source], [binary]):
                result = subprocess.run(argv, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                outputs.append(result.stdout)
            self.assertEqual(outputs[0], outputs[1])
            self.assertIn("PASS real actor refresh through concrete", outputs[0])
            run.evidence["status"] = "SESSION_UNIT_ONLY_NOT_NATIVE_REQUEST_ACCEPTANCE"
        finally:
            run.save()

    def test_child_free_git_version_matches_live_git_metadata_and_overrides(self):
        build = Path(tempfile.mkdtemp(prefix="git-version-", dir=HERE / "build"))
        root = build / "repository"
        root.mkdir()
        result = subprocess.run(["git", "init", "--quiet", root], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        (root / "config").mkdir()
        source = build / "probe.rb"
        source.write_text((HERE / "compat/discourse/lib/portable_git_version.rb").read_text() +
                          '\nputs JSON.generate(PortableGitVersion.read(ARGV.fetch(0)))\n')
        binary = build / "probe"
        result = subprocess.run([HERE.parent / "spinel/spinel", "--cc=clang", "--jobs=4", source, "-o", binary], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        def check(path, expected):
            for argv in (["ruby", source, path], [binary, path]):
                result = subprocess.run(argv, capture_output=True, text=True)
                self.assertEqual(result.returncode, 0, result.stderr)
                self.assertEqual(json.loads(result.stdout), expected)
        first, second = "1" * 40, "2" * 40
        head = root / ".git/HEAD"
        head.write_text(first + "\n")
        expected = subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip()
        check(root, expected)
        head.write_text("ref: refs/heads/unit\n")
        branch = root / ".git/refs/heads/unit"
        branch.write_text(second + "\n")
        check(root, subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip())
        branch.unlink()
        (root / ".git/packed-refs").write_text(f"# pack-refs with: peeled fully-peeled sorted\n{first} refs/heads/unit\n")
        check(root, subprocess.check_output(["git", "-C", root, "rev-parse", "HEAD"], text=True).strip())
        linked = build / "linked-worktree"
        linked.mkdir()
        (linked / ".git").write_text("gitdir: ../repository/.git/worktrees/unit\n")
        metadata = root / ".git/worktrees/unit"
        metadata.mkdir(parents=True)
        (metadata / "commondir").write_text("../..\n")
        (metadata / "HEAD").write_text("ref: refs/heads/unit\n")
        check(linked, first)
        override = root / "config/git-utils-overrides.json"
        override.write_text(json.dumps({"git_version": "hosting-override"}))
        check(root, "hosting-override")
        override.write_text(json.dumps({"git_version": False}))
        check(root, first)
        head.write_text("ref: refs/heads/absent\n")
        check(root, "unknown")
        empty = build / "not-a-repository"
        empty.mkdir()
        check(empty, "unknown")
        trace = build / "native.trace"
        result = subprocess.run(["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary, root], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        self.assertEqual(trace.read_text().count("execve("), 1)
        self.assertNotIn("connect(", trace.read_text())

    def test_locale_profile_refusals_execute_the_actual_shared_guards(self):
        build = Path(tempfile.mkdtemp(prefix="locale-profile-", dir=HERE / "build"))
        extractor = r'''require "prism"
owner = Prism.parse_file(ARGV[0]).value.statements.body.grep(Prism::ClassNode).find do |node|
  node.body.body.grep(Prism::DefNode).any? { |method| method.name == :with_resolved_locale_for_latest_json }
end
method = owner.body.body.grep(Prism::DefNode).find { |node| node.name == :with_resolved_locale_for_latest_json }
guards = method.body.body.select { |node| node.slice.include?("unsupported selected JSON locale override profile") || node.slice.include?("unsupported non-default JSON application locale profile") }
raise "locale guards changed" unless guards.length == 2
defaults = Prism.parse_file(ARGV[1]).value.statements.body.grep(Prism::ClassNode).first
constant = defaults.body.body.grep(Prism::ConstantWriteNode).find { |node| node.name == :DEFAULT_LOCALE }
puts "module SiteSettings; class DefaultsProvider; #{constant.slice}; end; end"
puts "def validate_locale_profile(locale_input, locale)\n#{guards.map(&:slice).join("\n")}\ntrue\nend"
'''
        result = subprocess.run(["ruby", "-e", extractor,
            HERE / "compat/discourse/app/controllers/application_controller.rb",
            HERE / "source/discourse/lib/site_settings/defaults_provider.rb"], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        source = build / "probe.rb"
        source.write_text(result.stdout + r'''
[nil, ""].each { |input| raise "default profile refused" unless validate_locale_profile(input, "en") }
["en", "fr", "en-US", "fr,en;q=0.5", "*", " "].each do |input|
  begin
    validate_locale_profile(input, "en")
    raise "selected override was accepted"
  rescue ArgumentError => error
    raise unless error.message.include?("unsupported selected JSON locale")
  end
end
begin
  validate_locale_profile(nil, "fr")
  raise "non-default application locale accepted"
rescue ArgumentError => error
  raise unless error.message.include?("unsupported non-default JSON application locale")
end
puts "PASS actual shared locale guard refusals, no fake setting/provider/actor"
''')
        binary = build / "probe"
        result = subprocess.run([HERE.parent / "spinel/spinel", "--cc=clang", "--jobs=4", source, "-o", binary], capture_output=True, text=True)
        self.assertEqual(result.returncode, 0, result.stderr)
        outputs = []
        for argv in (["ruby", source], [binary]):
            result = subprocess.run(argv, capture_output=True, text=True)
            self.assertEqual(result.returncode, 0, result.stderr)
            outputs.append(result.stdout)
        self.assertEqual(outputs[0], outputs[1])
        self.assertIn("PASS actual shared locale guard refusals", outputs[0])

    def test_stage4_trace_policy_keeps_only_two_readonly_pg_and_one_owned_cache_connection(self):
        pg = 'connect(3, {sin_port=htons(5499), sin_addr=inet_addr("127.0.0.1")}, 16)'
        cache = pg.replace("5499", "54807")
        trace = 'execve("actual-elf", [], []) = 0\n' + "\n".join([pg, pg, cache])
        fixture = {"port": 54807, "cleanup_complete": True}
        proof = validate_request_trace(trace, fixture)
        self.assertEqual(proof["pg_connections"], 2)
        for wrong in (trace + "\n" + cache, trace.replace("54807", "6399"),
                      trace.replace("127.0.0.1", "127.0.0.2"), trace.replace(cache, ""), trace + '\nexecve("ruby", [], [])'):
            with self.assertRaises(AssertionError):
                validate_request_trace(wrong, fixture)
        for wrong in ({"port": 6399, "cleanup_complete": True}, {"port": 54807, "cleanup_complete": False}):
            with self.assertRaises(AssertionError):
                validate_request_trace(trace, wrong)

    def test_processing_effect_controls_reject_omission_leak_and_wrong_types(self):
        row = {"path": "/latest.json", "status": 200, "headers": {"X-Request-Id": "01234567-0123-4567-89ab-0123456789ab"},
               "body": {}, "request_effects": {"processing_during_dispatch": True, "processing_after_dispatch": None,
                   "processing_during_profiler_save": True,
                   "profiler_authorized_after_dispatch": True,
                   "application_layout_preloader": {"allocated": True, "guardian_anonymous": True, "preloaded_empty": True,
                     "login_method": None, "theme_target": "desktop", "theme_id": -2},
                   "profiler_snapshot_fields": {"Application version": "test-source-version"},
                   "readonly_state": {"readonly": False, "staff_writes_only": False},
                   "request_locale": {"during_callbacks": "en", "after_dispatch": "fr"},
                   "request_id_visible_and_consistent": True,
                   "authorized_host_during_dispatch": "localhost",
                   "remote_ip_during_dispatch": {"value": "127.0.0.1", "lazy_class": "ActionDispatch::RemoteIp::GetIp"}}}
        comparable({"requests": [row]})
        for field, value in (("processing_during_dispatch", None), ("processing_during_dispatch", 1), ("processing_after_dispatch", True), ("processing_during_profiler_save", None),
                             ("profiler_authorized_after_dispatch", None), ("profiler_authorized_after_dispatch", 1),
                             ("request_id_visible_and_consistent", False), ("request_id_visible_and_consistent", 1),
                             ("authorized_host_during_dispatch", None), ("authorized_host_during_dispatch", 1),
                             ("remote_ip_during_dispatch", {"value": "203.0.113.1", "lazy_class": "ActionDispatch::RemoteIp::GetIp"}),
                             ("remote_ip_during_dispatch", {"value": "127.0.0.1", "lazy_class": None})):
            wrong = json.loads(json.dumps(row))
            wrong["request_effects"][field] = value
            with self.assertRaises(AssertionError):
                comparable({"requests": [wrong]})

    def test_supplied_request_id_requires_exact_context_not_uuid_waiver(self):
        row = {"path": "/latest.json", "status": 200, "headers": {"X-Request-Id": ""}, "body": {}}
        with self.assertRaises(AssertionError):
            comparable({"requests": [row]})
        result = comparable({"requests": [row]}, expected_request_ids={0: ""})
        self.assertEqual(result[0]["headers"]["x-request-id"], "")
        for wrong in ("wrong", "01234567-0123-4567-89ab-0123456789ab"):
            row["headers"]["X-Request-Id"] = wrong
            with self.assertRaises(AssertionError):
                comparable({"requests": [row]}, expected_request_ids={0: ""})

    def test_profiler_random_ids_require_real_store_proof_and_preserve_membership(self):
        def report(ids):
            rows = []
            for index, current in enumerate(ids):
                ordered = list(reversed(ids[:index + 1]))
                pages = [{"id": value, "request_method": "GET", "request_path": "/latest.json",
                          "user": "scoped-user", "root_name": "GET actual request",
                          "fields": ["root", "request_path"], "sql_count": 0} for value in ordered]
                rows.append({"path": "/latest.json", "status": 200, "body": {},
                    "headers": {"X-Request-Id": "01234567-0123-4567-89ab-0123456789ab",
                                "x-miniprofiler-ids": ",".join(ordered)},
                    "profiler_proof": {"current_id": current, "ordered_unviewed_ids": ordered,
                        "max_traces_to_show": 100, "stored_pages": pages}})
            return {"requests": rows}
        base = report(["a", "b", "c"])
        equal_records(comparable(base), comparable(report(["x", "y", "z"])))
        for mutation in ("missing_proof", "reordered_header", "missing_page", "reused_id", "missing_header"):
            wrong = json.loads(json.dumps(base))
            row = wrong["requests"][-1]
            if mutation == "missing_proof":
                del row["profiler_proof"]
            elif mutation == "reordered_header":
                row["headers"]["x-miniprofiler-ids"] = "c,a,b"
            elif mutation == "missing_page":
                row["profiler_proof"]["stored_pages"].pop()
            elif mutation == "reused_id":
                row["profiler_proof"]["current_id"] = "a"
            else:
                del row["headers"]["x-miniprofiler-ids"]
            with self.assertRaises((AssertionError, KeyError), msg=mutation):
                comparable(wrong)

    def test_comparison_keeps_all_headers_payload_types_and_errors(self):
        row = {"path": "/latest.json", "status": 200, "headers": {"Content-Length": "12", "X-Test": "kept",
               "X-Request-Id": "01234567-0123-4567-89ab-0123456789ab"}, "body": {"visible": True, "page": 1}}
        base = {"requests": [row]}
        changed = json.loads(json.dumps(base))
        changed["requests"][0]["headers"]["X-Request-Id"] = "11234567-0123-4567-89ab-0123456789ab"
        equal_records(comparable(base), comparable(changed))
        for key, value in (("Content-Length", "13"), ("X-Test", "wrong")):
            wrong = json.loads(json.dumps(base))
            wrong["requests"][0]["headers"][key] = value
            with self.assertRaises(AssertionError):
                equal_records(comparable(base), comparable(wrong))
        for key, value in (("visible", 1), ("page", 2)):
            wrong = json.loads(json.dumps(base))
            wrong["requests"][0]["body"][key] = value
            with self.assertRaises(AssertionError):
                equal_records(comparable(base), comparable(wrong))
        wrong = json.loads(json.dumps(base))
        wrong["requests"][0]["status"] = 400
        with self.assertRaises(AssertionError):
            equal_records(comparable(base), comparable(wrong))
        wrong["requests"][0]["headers"]["X-Request-Id"] = "not-a-UUID"
        with self.assertRaises(AssertionError):
            comparable(wrong)


if __name__ == "__main__":
    unittest.main()

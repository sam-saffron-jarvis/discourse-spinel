#!/usr/bin/env python3
"""Cumulative genuine JSON controller experiment: default compile AND RUN.

Unimplemented callbacks/middleware are NOT accepted. Compile/runtime/parity
failure exits nonzero; diagnostics cannot promote native request/page flags.
"""
import json
import os
import re
import secrets
import shutil
import argparse
from oracle_sandbox import ValkeySandbox

from probe_serialized_latest import SerializedLatestRun
from probe_latest_json_rails import comparable
from execute_latest_json_request import execute_request_core
from verify import HERE, ROOT, digest, equal_records

PATHS = ["/latest.json", "/latest.json?per_page=2&page=0", "/latest.json?per_page=2&page=1",
         "/latest.json?per_page=2&page=2", "/latest.json?per_page=3&order=created&ascending=true",
         "/latest.json?page=not-an-integer"]


class LatestJsonRequestRun(SerializedLatestRun):
    def command(self, name, argv, **kwargs):
        self.env["FIDELITY_STAGE4_MIDDLEWARE_MATRIX"] = "1" if name in ("native", "compat", "compat-preflight", "rails-oracle") or name.endswith("-overload-ignored") else "0"
        self.env["FIDELITY_STAGE4_READONLY_MATRIX"] = "1" if name in ("native", "compat", "compat-preflight", "rails-oracle") or name.endswith("-readonly-omitted-header") else "0"
        if name == "compat":
            for helper in ("latest_request_transport.rb", "owned_cache_policy.rb", "latest_profiler_store_probe.rb", "latest_layout_probe.rb", "request_lifecycle_probe.rb"):
                shutil.copyfile(self.path / helper, self.path / "compat" / helper)
        if name == "native-compile" and not (self.path / "compat-preflight.stdout").exists():
            self.compat_diagnostic()
        binary = str(self.path / "probe")
        uses_cache = name.startswith("compat") or (name != "native-compile" and binary in [str(value) for value in argv])
        if uses_cache:
            # The actual framework captures Rails.root from its serving cwd.
            # Multi-locale translations are real emitted application assets,
            # not files to fabricate in the immutable reference checkout.
            if name.startswith("compat"):
                tree = "compat-preflight" if name == "compat-preflight" or name.startswith("compat-preflight-") else "compat"
                kwargs["cwd"] = self.path / tree / "emitted"
                self.env["BUNDLE_GEMFILE"] = str(ROOT / "discourse/Gemfile")
            else:
                kwargs["cwd"] = self.path / "emitted"
            sandbox = ValkeySandbox(self.path / (name + "-cache-fixture"))
            prior = {}
            try:
                with sandbox:
                    configuration = {**sandbox.environment, "FIDELITY_CACHE_OWNER_PID": str(os.getpid())}
                    prior = {key: self.env.get(key) for key in configuration}
                    self.env.update(configuration)
                    result = super().command(name, argv, **kwargs)
                    output = (self.path / (name + ".stdout")).read_text()
                    effects = [json.loads(line.split(" ", 1)[1]) for line in output.splitlines() if line.startswith("FIDELITY_CACHE_EFFECT ")]
                    self.evidence.setdefault("owned_cache_runtime_effects", {})[name] = {"effects": effects,
                        "port": sandbox.port, "endpoint": "separately owned loopback fixture", "cleanup_complete": False}
                    if name == "native":
                        trace = (self.path / "native.trace").read_text()
                        self.validate_native_cache_connections(trace, sandbox.port)
            finally:
                for key, value in prior.items():
                    if value is None:
                        self.env.pop(key, None)
                    else:
                        self.env[key] = value
                self.evidence.setdefault("owned_cache_cleanup", {})[name] = sandbox.cleanup_complete
                if name in self.evidence.get("owned_cache_runtime_effects", {}):
                    self.evidence["owned_cache_runtime_effects"][name]["cleanup_complete"] = sandbox.cleanup_complete
                self.save()
        else:
            result = super().command(name, argv, **kwargs)
        if name == "native":
            output = (self.path / "native.stdout").read_text()
            self.evidence["native_request_entered"] = "FIDELITY_JSON_REQUEST_ENTER" in output
            self.evidence["native_request_executed"] = result[0] == 0 and "FIDELITY_JSON_REQUEST_MATERIALIZED" in output
        return result

    def validate_native_cache_connections(self, trace, port):
        connections = [line for line in trace.splitlines() if "connect(" in line]
        assert len(connections) == 3, connections
        assert sum("htons(5499)" in line for line in connections) == 2
        assert sum(f"htons({port})" in line for line in connections) == 1
        assert all('inet_addr("127.0.0.1")' in line for line in connections)

    def compat_diagnostic(self):
        from verify import ROOT
        target = self.path / "compat-preflight"
        shutil.copytree(self.path / "emitted", target / "emitted")
        for name in ("entry.rb", "probe.rb", "latest_request_transport.rb", "owned_cache_policy.rb", "latest_profiler_store_probe.rb", "latest_layout_probe.rb", "request_lifecycle_probe.rb"):
            shutil.copyfile(self.path / name, target / name)
        shutil.copyfile(ROOT / "roundhouse/runtime/spinel/pg_driver_cruby.rb", target / "emitted/runtime/pg_driver.rb")
        self.command("compat-preflight", ["bundle", "exec", "ruby", "--enable-frozen-string-literal", target / "entry.rb"],
                     cwd=ROOT / "discourse", timeout=120)
        self.evidence["same_lowered_cruby_diagnostic_completed"] = True

    def __init__(self):
        super().__init__()
        self.env["SECRET_KEY_BASE"] = secrets.token_hex(64)
        self.env["FIDELITY_JSON_REQUEST_REFERENCE_DIRECTORY"] = str(self.path)
        self.evidence.update(stage=__doc__, profile="bounded shared ListController JSON experiment",
                             json_request_accepted=False, full_query_accepted=False, page_accepted=False)

    def run_partial(self):
        # Stage4 explicitly permits its separately owned guarded cache fixture;
        # the historical PG-only runner/gates remain byte-for-byte unchanged.
        execute_request_core(self)
        original_url = self.env["DATABASE_URL"]
        self.env["DATABASE_URL"] = "postgres://discourse@127.0.0.1:6399/discourse_development"
        try:
            for runtime, argv in (("native", [self.path / "probe"]),
                    ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
                trace = self.path / f"{runtime}-wrong-endpoint.trace"
                code, _ = self.command(f"{runtime}-wrong-endpoint", ["strace", "-f", "-e", "trace=connect", "-o", trace, *argv],
                                       check=False, timeout=30)
                assert code != 0
                assert "portable security PG endpoint guard" in (self.path / f"{runtime}-wrong-endpoint.stderr").read_text()
                assert "connect(" not in trace.read_text(), "unapproved endpoint reached a socket"
        finally:
            self.env["DATABASE_URL"] = original_url
        self.evidence["endpoint_negatives_before_connect"] = True

    def prepare_serialization_stage_inputs(self, app):
        super().prepare_serialization_stage_inputs(app)
        self.command("project-latest-json-controller", ["ruby", HERE / "tools/project_latest_json_request.rb",
            HERE / "source/discourse", HERE / "compat/discourse", app], timeout=30)
        transport = HERE / "test/latest_request_transport.rb"
        target = self.path / "latest_request_transport.rb"
        target.write_bytes(transport.read_bytes())
        for name in ("owned_cache_policy.rb", "latest_profiler_store_probe.rb", "latest_layout_probe.rb", "request_lifecycle_probe.rb"):
            helper = HERE / "test" / name
            shutil.copyfile(helper, self.path / name)
            self.evidence.setdefault("request_test_helpers_sha256", {})[name] = digest(helper.read_bytes())
        self.evidence["request_test_transport_sha256"] = digest(transport.read_bytes())
        # The serializer's fixed nonnil TopicList root is a real Hash. This
        # source-owned return contract supplies no data, identity or payload.
        (app / "sig/request_profile.rbs").write_text('''class TopicListSerializer
  def as_json: (?Hash[untyped, untyped]) -> Hash[Symbol, untyped]
end
class SiteSetting
  def self.default_locale: () -> String
  def self.portable_allowed_theme_repos: () -> String?
  def self.portable_reject_anonymous_min_queue_seconds: () -> Float
  def self.portable_prepare_request_locale: (String) -> String
  def self.portable_cors_enabled?: () -> bool
  def self.portable_cors_origin: () -> String?
end
class ApplicationController
  def self.requires_login: (?Hash[Symbol, Array[Symbol | String]]) -> Hash[Symbol, Array[Symbol | String]]
  def self.requires_login_arg: () -> Hash[Symbol, Array[Symbol | String]]?
end
module Rack
  class MiniProfiler
    def self.add_snapshot_custom_field: (String, untyped) -> untyped
    def self.snapshots_transporter?: () -> bool
    def self.get_snapshot_custom_fields: () -> Hash[String, untyped]?
  end
end
class PortableReadonlyContext
  self.@redis: PortableNamespacedRedis?
  self.@configuration: SiteSettings::PortableGlobalConfiguration
  self.@redis_error_at: Time?
  def self.configure: (PortableRedisConnection, SiteSettings::PortableGlobalConfiguration, String) -> void
  def self.redis: () -> PortableNamespacedRedis
  def self.force?: () -> bool
  def self.redis_error_at: () -> Time?
end
class PortableNamespacedRedis
  def initialize: (PortableRedisConnection, String) -> void
  def get: (String) -> String?
  def exists?: (*String) -> bool
end
class PortableGitVersion
  self.@application_root: String?
  def self.configure_application_root: (String) -> String
  def self.application_root: () -> String
end
class PortableControllerLoginPolicy
  self.@arguments: Hash[String, Hash[Symbol, Array[Symbol | String]]]
  def self.set: (String, Hash[Symbol, Array[Symbol | String]]) -> Hash[Symbol, Array[Symbol | String]]
  def self.get: (String) -> Hash[Symbol, Array[Symbol | String]]?
end
''')

    def generate(self):
        super().generate()
        # This supported request profile needs actual IPAddr String case
        # equality and 128-bit IPv6 masks. Select the framework's full
        # stdlib/bundled provider on BOTH runtimes, not the default octet
        # port (whose narrower layout would overwrite the package class).
        runtime = self.path / "emitted/runtime"
        provider = runtime / "ipaddr_stdlib.rb"
        port = runtime / "ipaddr.rb"
        port_signature = runtime / "ipaddr.rbs"
        self.evidence["request_ipaddr_provider"] = {
            "source": "roundhouse/runtime/spinel/ipaddr_stdlib.rb",
            "selected_sha256": digest(provider.read_bytes()),
            "replaced_octet_port_sha256": digest(port.read_bytes()),
            "removed_port_layout_sha256": digest(port_signature.read_bytes()),
            "same_provider_on_cruby_and_native": True,
            "native_integer_mode": "promote",
            "reason": "HostAuthorization actual String case equality; no mixed IPAddr representations",
            "owning_regression": "cargo test --test spinel_ipaddr_package -- --include-ignored"}
        shutil.copyfile(provider, port)
        port_signature.unlink()
        # Analysis names Rails' canonical classes; this in-process framework
        # implements their concrete runtime counterparts. Bind declaration
        # names to those ACTUAL classes before seeding the native ABI. Keeping
        # opaque/nonexistent Rails names lost the real provider refresh method
        # at runtime (strict102454), despite identical Ruby passing on CRuby.
        bindings = {"ActionDispatch::Request::Session": "ActionDispatch::Session",
                    "ActionDispatch::Cookies::CookieJar": "ActionController::CookieJar"}
        rebound = {}
        for path in (self.path / "emitted").rglob("*.rbs"):
            before = path.read_bytes()
            text = before.decode()
            for original, actual in bindings.items():
                text = text.replace(original, actual)
            after = text.encode()
            if before != after:
                path.write_bytes(after)
                rebound[str(path.relative_to(self.path / "emitted"))] = {"before_sha256": digest(before), "after_sha256": digest(after)}
        translation_table = self.path / "emitted/config/i18n_translations"
        if translation_table.exists():
            self.evidence["request_compiled_translation_asset"] = {"path": "emitted/config/i18n_translations",
                "sha256": digest(translation_table.read_bytes()), "derived_from_pinned_YAML": True,
                "runtime_root": "actual emitted serving directory", "captured_translation_payload": False}
        self.evidence["request_concrete_runtime_type_bindings"] = {"bindings": bindings,
            "declarations": rebound, "application_Ruby_changed": False,
            "reason": "concrete framework session/cookie ABI, not fake classes or erased types"}
        # Only real request/controller runtime definitions, not the server
        # scaffold's boot, sockets, jobs or unrelated process cache stores.
        requires = ["runtime/base64", "runtime/json_impl", "runtime/action_controller_json_render",
                    "runtime/params", "runtime/action_dispatch", "runtime/action_dispatch/request",
                    "runtime/action_controller", "runtime/hash_to_query", "runtime/param_builder",
                    "runtime/inprocess_controller", "runtime/active_record/request_query_scope", "config/routes"]
        bootstrap = "\n".join('require_relative "' + name + '"' for name in requires) + "\n"
        (self.path / "emitted/inprocess_request_boot.rb").write_text(bootstrap)
        self.evidence["framework_request_bootstrap"] = {"requires": requires,
            "sha256": digest(bootstrap.encode()), "server_transport_or_jobs_loaded": False,
            "whole_boot_or_callback_equivalence_accepted": False}
        entry = self.path / "entry.rb"
        text = entry.read_text()
        marker = 'require_relative "probe"'
        assert text.count(marker) == 1
        namespace_source = HERE / "source/framework/rails_multisite-9.0.0/lib/rails_multisite/connection_management.rb"
        namespace_text = namespace_source.read_text()
        namespace_matches = re.findall(r'^    DEFAULT = ("[^"\n]+")$', namespace_text, re.MULTILINE)
        assert len(namespace_matches) == 1, "source default application-cache namespace changed"
        cache_namespace = json.loads(namespace_matches[0])
        self.evidence["request_cache_namespace_declaration"] = {"source": str(namespace_source.relative_to(HERE)),
            "sha256": digest(namespace_source.read_bytes()), "declaration": "DEFAULT = " + namespace_matches[0],
            "configured_multisite_supported": False, "captured_runtime_value": False}
        profiler_boot = f'''require_relative "emitted/inprocess_request_boot"
require {json.dumps(str(HERE / "compat/framework/portable_redis_connection.rb"))}
require {json.dumps(str(HERE / "compat/framework/portable_profiler_bootstrap.rb"))}
require_relative "owned_cache_policy"
require_relative "latest_profiler_store_probe"
require_relative "latest_request_transport"
cache_policy = OwnedCachePolicy.new
cache_connection = cache_policy.connect
PortableProfilerBootstrap.configure(settings_configuration, cache_connection)
# Logical application source/configuration root already used by the settings
# bootstrap; Git metadata are read live, not supplied as an observed SHA.
PortableGitVersion.configure_application_root({json.dumps(str(ROOT / "discourse"))})
# RailsMultisite9.0.0 ConnectionManagement::DEFAULT (single-site only);
# the existing database_hostname guard refuses a configured multisite.yml.
settings_configuration.database_hostname
PortableReadonlyContext.configure(cache_connection, settings_configuration, {json.dumps(cache_namespace)})
LatestRequestProbe.configure_profiler(cache_policy, cache_connection)
'''
        text = text.replace(marker, profiler_boot + marker)
        entry.write_text(text + "\ncache_connection.close\n")
        probe = self.path / "probe.rb"
        request_lines = "\n".join('puts "FIDELITY_REQUEST " + FidelityDriver.encode(LatestRequestProbe.call(' + json.dumps(path) + '))' for path in PATHS)
        controls = '''credential_profile = ENV["FIDELITY_STAGE4_CREDENTIAL_PROFILE"]
login_profile = ENV["FIDELITY_STAGE4_LOGIN_POLICY"]
host_profile = ENV["FIDELITY_STAGE4_HOST_PROFILE"]
ingress_profile = ENV["FIDELITY_STAGE4_INGRESS_PROFILE"]
if ingress_profile
  extra = {}
  case ingress_profile
  when "client-ip" then extra["HTTP_CLIENT_IP"] = "203.0.113.7"
  when "forwarded" then extra["HTTP_FORWARDED"] = "for=203.0.113.7"
  when "x-forwarded-for" then extra["HTTP_X_FORWARDED_FOR"] = "203.0.113.7"
  when "nil-forwarded" then extra["HTTP_X_FORWARDED_FOR"] = nil
  when "proxy-host" then extra["HTTP_X_FORWARDED_HOST"] = "attacker.invalid"
  when "alternate-peer" then extra["REMOTE_ADDR"] = "192.0.2.1"
  when "missing-peer" then extra["REMOTE_ADDR"] = nil
  when "method" then extra["REQUEST_METHOD"] = "POST"
  when "path" then extra["PATH_INFO"] = "/auth/login"
  when "conditional" then extra["HTTP_IF_NONE_MATCH"] = "token"
  when "body" then extra["rack.input"] = "body"
  when "prebound" then extra["action_dispatch.remote_ip"] = "203.0.113.7"
  when "query-override" then extra["QUERY_STRING"] = "page=999"
  when "scheme-override" then extra["rack.url_scheme"] = "https"
  when "script-override" then extra["SCRIPT_NAME"] = "/other"
  when "parameters-override" then extra["action_dispatch.request.parameters"] = "untrusted"
  when "server-name-override" then extra["SERVER_NAME"] = "attacker.invalid"
  when "unknown-server" then extra["arbitrary.server.context"] = "untrusted"
  when "overload-client-ip"
    extra["HTTP_X_REQUEST_START"] = "t=1"
    extra["HTTP_CLIENT_IP"] = "203.0.113.7"
  else raise "unknown ingress negative"
  end
  begin
    LatestRequestProbe.call("/latest.json", extra)
    raise "unsupported ingress admitted"
  rescue ArgumentError => error
    raise unless error.message.start_with?("unsupported JSON ingress")
    raise "ingress leaked controller context" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil?
    raise "ingress leaked profiler context" unless Rack::MiniProfiler.current.nil?
    raise "ingress leaked processing context" unless Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY].nil?
    raise "ingress leaked locale scope" unless I18n.locale == :fr
    puts "FIDELITY_INGRESS_CONTROL " + JSON.generate({profile: ingress_profile, guard: error.message, context_cleanup: true})
  end
elsif host_profile
  refused = false
  unsafe_200 = false
  unsafe_request = nil
  begin
    result = LatestRequestProbe.call("/latest.json", {"HTTP_HOST" => "attacker.invalid"})
    raise "host guard unexpectedly admitted request" unless host_profile == "ignored-blocked"
    unsafe_200 = result[:status] == 200 && !result[:body]["topic_list"]["topics"].empty? &&
      result[:request_effects][:authorized_host_during_dispatch].nil?
    raise "ignored host guard control did not execute real unsafe response" unless unsafe_200
    unsafe_request = result
  rescue ArgumentError => error
    raise unless host_profile == "blocked" && error.message == "unsupported blocked-host JSON request profile"
    refused = true
  end
  raise "host profile leaked controller context" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil?
  raise "host profile leaked profiler context" unless Rack::MiniProfiler.current.nil?
  raise "host profile leaked processing context" unless Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY].nil?
  raise "host profile leaked locale" unless I18n.locale == :fr
  puts "FIDELITY_HOST_CONTROL " + JSON.generate({profile: host_profile, refused: refused, unsafe_200: unsafe_200, context_cleanup: true, request: unsafe_request})
elsif login_profile
  options = {}
  options[:only] = [:latest] if login_profile == "only-latest"
  options[:except] = [:other] if login_profile == "except-other"
  if ENV.fetch("FIDELITY_STAGE4_OMIT_LOGIN_GUARD", "0") == "1"
    IgnoredRequiresLoginController.requires_login(options)
  else
    ObservedLatestController.requires_login(options)
  end
  denied = false
  begin
    LatestRequestProbe.call("/latest.json")
  rescue Discourse::NotLoggedIn
    denied = true
  end
  raise "login policy leaked controller context" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil?
  raise "login policy leaked profiler context" unless Rack::MiniProfiler.current.nil?
  raise "login policy leaked processing context" unless Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY].nil?
  raise "login policy leaked locale scope" unless I18n.locale == :fr
  puts "FIDELITY_LOGIN_POLICY_CONTROL " + JSON.generate({profile: login_profile, denied: denied, context_cleanup: true})
elsif credential_profile
  path = "/latest.json"
  headers = {}
  case credential_profile
  when "api-key" then headers["HTTP_API_KEY"] = "invalid-stage4-test-key"
  when "user-api-key" then headers["HTTP_USER_API_KEY"] = "invalid-stage4-test-key"
  when "authorization" then headers["HTTP_AUTHORIZATION"] = "Bearer invalid-stage4-test-key"
  when "cookie" then headers["HTTP_COOKIE"] = "_t=invalid-stage4-test-token"
  when "preauthenticated" then headers["_DISCOURSE_CURRENT_USER"] = "invalid-stage4-test-context"
  when "preauthenticated-api" then headers["_DISCOURSE_API"] = "invalid-stage4-test-context"
  when "preauthenticated-user-api" then headers["_DISCOURSE_USER_API"] = "invalid-stage4-test-context"
  when "overload-api-key"
    headers["HTTP_X_REQUEST_START"] = "t=1"
    headers["HTTP_API_KEY"] = "invalid-stage4-test-key"
  when "overload-cookie"
    headers["HTTP_X_REQUEST_START"] = "t=1"
    headers["HTTP_COOKIE"] = "_t=invalid-stage4-test-token"
  when "overload-preauthenticated-cookie"
    headers["HTTP_X_REQUEST_START"] = "t=1"
    headers["_DISCOURSE_DECRYPTED_AUTH_COOKIE"] = "invalid-stage4-test-context"
  when "query" then path = "/latest.json?user_api_public_key=invalid-stage4-test-key"
  else raise "unknown credential negative"
  end
  begin
    LatestRequestProbe.call(path, headers)
    raise "credential was accepted as anonymous"
  rescue ArgumentError => error
    raise unless error.message.include?("unsupported")
    raise "credential leaked controller context" unless ActionController::Current.request.nil? && ActionController::Current.controller.nil?
    raise "credential leaked profiler context" unless Rack::MiniProfiler.current.nil?
    raise "credential leaked processing context" unless Thread.current[Middleware::ProcessingRequest::PROCESSING_REQUEST_THREAD_KEY].nil?
    raise "credential leaked locale scope" unless I18n.locale == :fr
    puts "FIDELITY_CREDENTIAL_CONTROL " + JSON.generate({profile: credential_profile, refused: true, context_cleanup: true})
  end
else
'''
        header_proof = HERE / "test/default_headers_profile_proof.rb"
        self.evidence["default_headers_test_consumer_sha256"] = digest(header_proof.read_bytes())
        probe.write_text(probe.read_text() + "\n" + header_proof.read_text() + '\nDefaultHeadersProfileProof.run\nputs "FIDELITY_JSON_REQUEST_ENTER"\n' + controls + request_lines +
                         '\nLatestRequestProbe.run_readonly_matrix\nLatestRequestProbe.run_request_id_matrix\nLatestRequestProbe.run_cors_matrix\nLatestRequestProbe.run_host_matrix\nLatestRequestProbe.run_remote_ip_matrix\nLatestRequestProbe.run_overload_matrix\nputs "FIDELITY_JSON_REQUEST_MATERIALIZED"\nend\n')

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/latest_json_request_oracle.rb", self.path / "probe.rb"]

    def provenance(self):
        super().provenance()
        manifest_name = "progressive/stage4_request/MANIFEST.json"
        manifest = json.loads((HERE / manifest_name).read_text())
        main = json.loads((HERE / "compat/MANIFEST.json").read_text())
        assert digest((HERE / manifest_name).read_bytes()) == main["supplementary_source_manifests"][manifest_name]
        for name, expected in manifest["source_sha256"].items():
            assert digest((HERE / "source/discourse" / name).read_bytes()) == expected
        for change in manifest["guarded_changes"]:
            source = (HERE / "source/discourse" / change["source"]).read_bytes()
            assert digest(source[change["start_byte"]:change["end_byte"]]) == change["text_sha256"]
        for name, expected in manifest["candidate_source_sha256"].items():
            assert digest((HERE / "compat/discourse" / name).read_bytes()) == expected
        self.evidence["request_source_manifest"] = manifest
        profiler_name = "progressive/stage4_request/PROFILER_SOURCE_MANIFEST.json"
        profiler = json.loads((HERE / profiler_name).read_text())
        assert digest((HERE / profiler_name).read_bytes()) == main["supplementary_source_manifests"][profiler_name]
        for name, expected in profiler["source_sha256"].items():
            source = (HERE / "source/framework" / name).read_bytes()
            assert digest(source) == expected
        for part in profiler["selected_spans"]:
            source = (HERE / "source/framework" / part["source"]).read_bytes()
            assert digest(source[part["start_byte"]:part["end_byte"]]) == part["text_sha256"]
        for name, expected in profiler["application_source_sha256"].items():
            assert digest((HERE / "source/discourse" / name).read_bytes()) == expected
        for name, expected in profiler["shared_components_sha256"].items():
            assert digest((HERE / name).read_bytes()) == expected
        profile_middleware = profiler["json_profile_middleware"]
        assert digest((HERE / profile_middleware["candidate"]).read_bytes()) == profile_middleware["candidate_sha256"]
        assert profile_middleware["whole_stack_accepted"] is False and profile_middleware["full_optional_features_accepted"] is False
        for name, expected in profile_middleware["application_source_sha256"].items():
            assert digest((HERE / "source/discourse" / name).read_bytes()) == expected
        for part in profile_middleware["selected_spans"]:
            base = HERE / ("source/framework" if part["source"].startswith("rack-") else "source/discourse")
            source = (base / part["source"]).read_bytes()
            assert digest(source[part["start_byte"]:part["end_byte"]]) == part["text_sha256"]
        for name, expected in profiler["query_cache_lifecycle"]["runtime_sha256"].items():
            assert digest((ROOT / name).read_bytes()) == expected
        response_middleware = profiler["response_middleware"]
        assert response_middleware["baseline_revision"] == manifest["baseline_revision"]
        for name, expected in response_middleware["source_sha256"].items():
            assert digest((ROOT / "discourse" / name).read_bytes()) == expected
        for part in response_middleware["selected_spans"]:
            source = (ROOT / "discourse" / part["source"]).read_bytes()
            assert digest(source[part["start_byte"]:part["end_byte"]]) == part["text_sha256"]
        assert digest((HERE / response_middleware["candidate"]).read_bytes()) == response_middleware["candidate_sha256"]
        assert digest((HERE / response_middleware["request_id_candidate"]).read_bytes()) == response_middleware["request_id_candidate_sha256"]
        for name, expected in response_middleware["framework_source_sha256"].items():
            assert digest((HERE / "source/framework" / name).read_bytes()) == expected
        assert digest((HERE / response_middleware["cors_candidate"]).read_bytes()) == response_middleware["cors_candidate_sha256"]
        assert response_middleware["full_stack_accepted"] is False
        assert response_middleware["observed_payloads_as_inputs"] is False
        assert digest((HERE / profiler["candidate"]).read_bytes()) == profiler["candidate_sha256"]
        host = profiler["host_authorization"]
        assert digest((HERE / host["candidate"]).read_bytes()) == host["candidate_sha256"]
        for name, expected in host["application_source_sha256"].items():
            assert digest((ROOT / "discourse" / name).read_bytes()) == expected
        for part in host["application_selected_spans"]:
            source = (ROOT / "discourse" / part["source"]).read_bytes()
            assert digest(source[part["start_byte"]:part["end_byte"]]) == part["text_sha256"]
        for name, expected in host["auxiliary_source_sha256"].items():
            assert digest((ROOT / name).read_bytes()) == expected
        assert host["full_stack_accepted"] is False and host["captured_permissions_or_runtime_hosts"] is False
        binding = profiler["request_id_framework_binding"]
        assert binding["full_stack_accepted"] is False
        for name, expected in binding["implementations_sha256"].items():
            assert digest((ROOT / name).read_bytes()) == expected
        self.evidence["profiler_source_manifest"] = profiler
        for name, expected in self.evidence.get("request_test_helpers_sha256", {}).items():
            assert digest((HERE / "test" / name).read_bytes()) == expected
            assert digest((self.path / name).read_bytes()) == expected
        path = self.path / "input/request-read-components.json"
        if path.exists():
            component = json.loads(path.read_text())
            for part in component["parts"]:
                root = "compat/discourse" if part["candidate"] else "source/discourse"
                source = (HERE / root / part["source"]).read_bytes()
                assert digest(source) == part["source_sha256"]
                assert digest(source[part["start_byte"]:part["end_byte"]]) == part["text_sha256"]
            for name, expected in component["generated_sha256"].items():
                assert digest((self.path / "input" / name).read_bytes()) == expected
            self.evidence["request_read_components"] = component
        if self.evidence.get("request_test_transport_sha256"):
            expected = self.evidence["request_test_transport_sha256"]
            assert digest((HERE / "test/latest_request_transport.rb").read_bytes()) == expected
            assert digest((self.path / "latest_request_transport.rb").read_bytes()) == expected

    def request_records(self, name):
        prefix = "FIDELITY_REQUEST "
        return [json.loads(line[len(prefix):]) for line in (self.path / (name + ".stdout")).read_text().splitlines() if line.startswith(prefix)]

    def readonly_records(self, name):
        prefix = "FIDELITY_READONLY_REQUEST "
        return [json.loads(line[len(prefix):]) for line in (self.path / (name + ".stdout")).read_text().splitlines() if line.startswith(prefix)]

    def compare_readonly_requests(self):
        profiles = ["site", "staff", "recent-pg", "stale-pg", "local-error", "cleared", "site-invalid-page"]
        reference = self.readonly_records("rails-oracle")
        assert [row["profile"] for row in reference] == profiles
        all_reference = comparable({"requests": self.request_records("rails-oracle") + [row["request"] for row in reference]})
        for runtime in ("native", "compat"):
            rows = self.readonly_records(runtime)
            assert [row["profile"] for row in rows] == profiles
            for row in rows:
                mode = row["profile"]
                request = row["request"]
                if mode == "site-invalid-page":
                    assert request["status"] == 400 and "topic_list" not in request["body"]
                    assert "discourse-readonly" not in {key.lower() for key in request["headers"]}, "after filter ran through outer error rescue"
                else:
                    assert request["status"] == 200 and request["body"]["topic_list"]["topics"]
                assert request["request_effects"]["readonly_state"] == {
                    "readonly": mode not in ("stale-pg", "cleared"), "staff_writes_only": mode == "staff"}
            equal_records(all_reference, comparable({"requests": self.request_records(runtime) + [row["request"] for row in rows]}))
        self.evidence["actual_readonly_request_matrix"] = {"profiles": profiles, "three_runtime_complete_response_and_effect_parity": True,
            "actual_owned_cache_flags_recency_and_process_error_state": True, "cleared_after_matrix": True,
            "timestamp_distributed_cache_effect_equivalence_accepted": False}

    def overload_records(self, name):
        prefix = "FIDELITY_OVERLOAD_REQUEST "
        return [json.loads(line[len(prefix):]) for line in (self.path / (name + ".stdout")).read_text().splitlines() if line.startswith(prefix)]

    def compare_overload_requests(self):
        def normalize(rows):
            assert [row["profile"] for row in rows] == ["seconds", "milliseconds"]
            result = []
            for row in rows:
                request = row["request"]
                headers = {key.lower(): value for key, value in request["headers"].items()}
                assert request["status"] == 503 and headers == {"content-type": "text/plain"}
                assert request["request_effects"] == {"controller_dispatched": False, "profiler_saved": False,
                    "processing_after_dispatch": None, "queue_above_threshold": True}
                result.append({"profile": row["profile"], "status": request["status"], "headers": headers,
                               "body": request["body"], "request_effects": request["request_effects"]})
            return result
        reference = normalize(self.overload_records("rails-oracle"))
        for runtime in ("native", "compat"):
            equal_records(reference, normalize(self.overload_records(runtime)))
        self.evidence["actual_overload_request_matrix"] = {"header_formats": ["seconds", "milliseconds"],
            "three_runtime_complete_503_response_and_scope_equal": True,
            "real_queue_parser_and_live_threshold": True, "no_controller_or_profiler_entry": True}

    def compare_request_id_requests(self):
        def records(name):
            prefix = "FIDELITY_REQUEST_ID_REQUEST "
            return [json.loads(line[len(prefix):]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                    if line.startswith(prefix)]
        all_rows = {}
        for runtime in ("rails-oracle", "native", "compat"):
            rows = records(runtime)
            assert [row["profile"] for row in rows] == ["supplied", "unicode-blank"]
            for row in rows:
                headers = {key.lower(): value for key, value in row["request"]["headers"].items()}
                assert row["request"]["request_effects"]["request_id_visible_and_consistent"] is True
                if row["profile"] == "supplied":
                    assert headers["x-request-id"] == "01234567-0123-4567-89ab-0123456789ab"
                else:
                    assert headers["x-request-id"] == "", "Discourse fast_blank treats NBSP as present before sanitizing to empty"
            prior = self.request_records(runtime) + [row["request"] for row in self.readonly_records(runtime)]
            all_rows[runtime] = comparable({"requests": prior + [row["request"] for row in rows]},
                expected_request_ids={len(prior): "01234567-0123-4567-89ab-0123456789ab", len(prior) + 1: ""})
        for runtime in ("native", "compat"):
            equal_records(all_rows["rails-oracle"], all_rows[runtime])
        self.evidence["actual_request_id_matrix"] = {"profiles": ["supplied", "unicode-blank"],
            "three_runtime_full_response_equal": True, "supplied_id_exact_not_normalized_before_assertion": True,
            "id_visible_before_controller_and_matches_response": True}

    def cors_records(self, name):
        prefix = "FIDELITY_CORS_REQUEST "
        return [json.loads(line[len(prefix):]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                if line.startswith(prefix)]

    def compare_cors_requests(self):
        all_rows = {}
        configured = self.evidence.get("cors_configuration_profile") == "enabled"
        for runtime in ("rails-oracle", "native", "compat"):
            rows = self.cors_records(runtime)
            assert [row["profile"] for row in rows] == ["absent", "allowed", "disallowed"]
            for row in rows:
                request = row["request"]
                headers = {key.lower(): value for key, value in request["headers"].items()}
                origins = request["request_effects"]["cors_origins_during_dispatch"]
                if configured:
                    assert origins[:2] == ["https://cors-a.invalid", "https://cors-b.invalid"]
                if origins is None:
                    assert "access-control-allow-origin" not in headers
                else:
                    assert type(origins) is list and origins and all(type(value) is str for value in origins)
                    expected = "https://cors-b.invalid" if row["profile"] == "allowed" and "https://cors-b.invalid" in origins else origins[0]
                    assert headers["access-control-allow-origin"] == expected
                    assert headers["access-control-allow-credentials"] == "true"
                    assert headers["access-control-allow-methods"] == "POST, PUT, GET, OPTIONS, DELETE"
                    assert headers["access-control-max-age"] == "7200"
            prefix = "FIDELITY_REQUEST_ID_REQUEST "
            ids = [json.loads(line[len(prefix):])["request"] for line in (self.path / (runtime + ".stdout")).read_text().splitlines()
                   if line.startswith(prefix)]
            prior = self.request_records(runtime) + [row["request"] for row in self.readonly_records(runtime)]
            expected_ids = {len(prior): "01234567-0123-4567-89ab-0123456789ab", len(prior) + 1: ""}
            all_rows[runtime] = comparable({"requests": prior + ids + [row["request"] for row in rows]}, expected_request_ids=expected_ids)
        for runtime in ("native", "compat"):
            equal_records(all_rows["rails-oracle"], all_rows[runtime])
        self.evidence["actual_cors_request_matrix"] = {"profiles": ["absent", "allowed", "disallowed"],
            "configuration_profile": "enabled" if configured else "ambient",
            "three_runtime_full_response_and_before_controller_env_equal": True,
            "live_configuration_inputs_not_captured_effective_values": True}

    def host_records(self, name):
        prefix = "FIDELITY_HOST_REQUEST "
        return [json.loads(line[len(prefix):]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                if line.startswith(prefix)]

    def compare_host_requests(self):
        expected_hosts = {"nested-localhost": "a.b.localhost", "test-domain": "one.test",
                          "ipv4": "127.0.0.1", "ipv6": "[2001:db8::1]"}
        all_rows = {}
        for runtime in ("rails-oracle", "native", "compat"):
            rows = self.host_records(runtime)
            assert [row["profile"] for row in rows] == list(expected_hosts)
            for row in rows:
                assert row["request"]["status"] == 200 and row["request"]["body"]["topic_list"]["topics"]
                assert row["request"]["request_effects"]["authorized_host_during_dispatch"] == expected_hosts[row["profile"]]
            prefix = "FIDELITY_REQUEST_ID_REQUEST "
            ids = [json.loads(line[len(prefix):])["request"] for line in (self.path / (runtime + ".stdout")).read_text().splitlines()
                   if line.startswith(prefix)]
            prior = self.request_records(runtime) + [row["request"] for row in self.readonly_records(runtime)]
            expected_ids = {len(prior): "01234567-0123-4567-89ab-0123456789ab", len(prior) + 1: ""}
            all_rows[runtime] = comparable({"requests": prior + ids + [row["request"] for row in self.cors_records(runtime)] +
                [row["request"] for row in rows]}, expected_request_ids=expected_ids)
        for runtime in ("native", "compat"):
            equal_records(all_rows["rails-oracle"], all_rows[runtime])
        self.evidence["actual_host_authorization_request_matrix"] = {"profiles": list(expected_hosts),
            "real_original_permissions_and_source_development_configuration": True,
            "three_runtime_full_response_and_pre_controller_authorization_equal": True,
            "blocked_host_debug_HTML_profile_accepted": False}

    def compare_remote_ip_requests(self):
        prefix = "FIDELITY_REMOTE_IP_REQUEST "
        rows = {}
        for runtime in ("rails-oracle", "native", "compat"):
            records = [json.loads(line[len(prefix):]) for line in (self.path / (runtime + ".stdout")).read_text().splitlines() if line.startswith(prefix)]
            assert len(records) == 1 and records[0]["profile"] == "direct-ipv6"
            row = records[0]["request"]
            assert row["status"] == 200 and row["body"]["topic_list"]["topics"]
            assert row["request_effects"]["remote_ip_during_dispatch"] == {"value": "::1", "lazy_class": "ActionDispatch::RemoteIp::GetIp"}
            # This peer has its own genuine profiler user/store ranking.
            rows[runtime] = comparable({"requests": [row]})
        equal_records(rows["rails-oracle"], rows["native"])
        equal_records(rows["rails-oracle"], rows["compat"])
        self.evidence["actual_remote_ip_request_matrix"] = {"profiles": ["direct-ipv4", "direct-ipv6"],
            "three_runtime_full_response_and_real_lazy_IP_equal": True, "forwarded_profiles_accepted": False}

    def compare_requests(self):
        reference = self.request_records("rails-oracle")
        assert len(reference) == len(PATHS)
        assert [row["status"] for row in reference] == [200] * 5 + [400]
        payload_status = lambda rows: [{key: row[key] for key in ("path", "status", "body")} for row in rows]
        for name in ("native", "compat"):
            equal_records(payload_status(reference), payload_status(self.request_records(name)))
        self.evidence["request_full_payload_types_status_paging_and_400_equal"] = True
        original = comparable({"requests": reference})
        for name in ("native", "compat"):
            equal_records(original, comparable({"requests": self.request_records(name)}))
        header_proofs = {}
        for runtime in ("rails-oracle", "native", "compat"):
            records = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (runtime + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_DEFAULT_HEADERS_PROFILE ")]
            assert len(records) == 1 and records[0]["omitted_guard_rejected"] is True
            header_proofs[runtime] = records[0]
        equal_records(header_proofs["rails-oracle"], header_proofs["native"])
        equal_records(header_proofs["rails-oracle"], header_proofs["compat"])
        wrong = json.loads(json.dumps(header_proofs["native"]))
        wrong["rows"][0]["headers"]["X-Content-Type-Options"] = "deliberately-wrong"
        try:
            equal_records(header_proofs["rails-oracle"], wrong)
        except AssertionError:
            self.evidence["default_headers_wrong_value_rejected"] = True
        else:
            raise AssertionError("wrong default header accepted")
        self.evidence["actual_default_headers_profile"] = header_proofs
        self.evidence["complete_request_parity"] = True
        self.compare_readonly_requests()
        self.compare_request_id_requests()
        self.compare_cors_requests()
        self.compare_host_requests()
        self.compare_remote_ip_requests()
        self.compare_overload_requests()

    def query_cache_lifecycle_controls(self):
        from request_lifecycle_contract import require_query_cache_lifecycle
        reference = self.request_records("rails-oracle")[0]["profiler_proof"]["original_framework_lifecycle_contracts"]
        controls = []
        for runtime, argv in (("native", [self.path / "probe"]), ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
            for label, flag in (("omitted-query-cache", "FIDELITY_STAGE4_OMIT_QUERY_CACHE"), ("early-query-cache-complete", "FIDELITY_STAGE4_EARLY_QUERY_CACHE_COMPLETE")):
                name = f"{runtime}-stage4-{label}"
                self.env[flag] = "1"
                try:
                    self.command(name, argv, timeout=90)
                finally:
                    self.env.pop(flag, None)
                rows = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (name + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_CANDIDATE_REQUEST_LIFECYCLE ")]
                assert rows and all(row["query_cache_enabled_during_controller"] is False and row["query_cache_enabled_after_response"] is False for row in rows)
                assert self.request_records(name)[0]["status"] == 200 and self.request_records(name)[0]["body"]["topic_list"]["topics"]
                try:
                    require_query_cache_lifecycle(reference, rows[0])
                except AssertionError:
                    controls.append({"runtime": runtime, "control": label, "real_successful_response_with_missing_lifecycle_rejected": True})
                else:
                    raise AssertionError("missing query-cache hook accepted")
        self.evidence["query_cache_lifecycle_negative_controls"] = controls

    def context_and_queries_controls(self):
        from request_lifecycle_contract import require_context_and_queries_lifecycle
        reference = self.request_records("rails-oracle")[0]["profiler_proof"]["original_framework_lifecycle_contracts"]
        controls = []
        for runtime, argv in (("native", [self.path / "probe"]), ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
            for label, flag in (("omitted-pool-completion", "FIDELITY_STAGE4_OMIT_POOL_COMPLETION"),
                                ("early-pool-completion", "FIDELITY_STAGE4_EARLY_POOL_COMPLETION"),
                                ("omitted-interlock", "FIDELITY_STAGE4_OMIT_INTERLOCK"),
                                ("leaked-interlock", "FIDELITY_STAGE4_LEAK_INTERLOCK"),
                                ("wrong-interlock-order", "FIDELITY_STAGE4_WRONG_INTERLOCK_ORDER"),
                                ("omitted-execution-context", "FIDELITY_STAGE4_OMIT_EXEC_CONTEXT"),
                                ("omitted-query-session", "FIDELITY_STAGE4_OMIT_QUERY_SESSION"),
                                ("leaked-execution-context", "FIDELITY_STAGE4_LEAK_EXEC_CONTEXT"),
                                ("leaked-query-session", "FIDELITY_STAGE4_LEAK_QUERY_SESSION")):
                name = f"{runtime}-stage4-{label}"
                self.env[flag] = "1"
                try:
                    self.command(name, argv, cwd=ROOT / "discourse", timeout=60)
                finally:
                    del self.env[flag]
                records = self.request_records(name)
                assert records[0]["status"] == 200 and records[0]["body"]["topic_list"]["topics"], "negative did not render real topics"
                rows = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                        if line.startswith("FIDELITY_CANDIDATE_REQUEST_LIFECYCLE ")]
                assert rows, "no actual negative lifecycle observation"
                try:
                    require_context_and_queries_lifecycle(reference, rows[0])
                except AssertionError as error:
                    controls.append({"runtime": runtime, "control": label, "actual_mismatch": str(error),
                                     "successful_real_response_with_missing_lifecycle_rejected": True})
                else:
                    raise AssertionError("omitted/leaked context/session accepted")
        self.evidence["context_and_queries_lifecycle_negative_controls"] = controls

    def require_supported_request_lifecycle(self):
        from request_lifecycle_contract import require_query_cache_lifecycle, require_context_and_queries_lifecycle
        reference = self.request_records("rails-oracle")[0]["profiler_proof"]["original_framework_lifecycle_contracts"]
        references = []
        for line in (self.path / "rails-oracle.stdout").read_text().splitlines():
            if not line.startswith("FIDELITY_") or " " not in line:
                continue
            try:
                payload = json.loads(line.split(" ", 1)[1])
            except json.JSONDecodeError:
                continue
            if not isinstance(payload, dict):
                continue
            record = payload.get("request", payload)
            proof = record.get("profiler_proof") if isinstance(record, dict) else None
            if isinstance(proof, dict) and proof.get("original_framework_lifecycle_contracts"):
                references.append(proof["original_framework_lifecycle_contracts"])
        assert references and references[0] == reference
        observations = {}
        for runtime in ("native", "compat"):
            rows = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (runtime + ".stdout")).read_text().splitlines()
                    if line.startswith("FIDELITY_CANDIDATE_REQUEST_LIFECYCLE ")]
            assert rows, "no executed candidate lifecycle observations"
            observations[runtime] = rows
        self.evidence["actual_request_lifecycle_contracts"] = {"original": reference, "original_per_request": references, "candidate": observations,
            "pool_entry_state_is_compared_per_request_not_frozen_from_first_bootstrap": True,
            "pool_held_at_query_completion_is_diagnostic_not_order_proof": True,
            "all_executor_hooks_accepted": False, "whole_request_accepted": False,
            "original_observation_is_not_candidate_runtime_input": True}
        self.save()
        self.command("request-lifecycle-comparator-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_request_lifecycle_contract.py", "-v"], timeout=30)
        for runtime, rows in observations.items():
            assert len(rows) == len(references), (runtime, len(rows), len(references))
            for original, row in zip(references, rows):
                require_query_cache_lifecycle(original, row)
                require_context_and_queries_lifecycle(original, row)
        pending = []
        for phase in ("run", "complete"):
            for callback in reference[f"executor_{phase}_callbacks"]:
                implemented = callback["hook"] in ("ActiveRecord::QueryCache::ExecutorHooks", "ActiveRecord::AsynchronousQueriesTracker", "Rails::Application::Finisher::InterlockHook", "ActiveRecord::ConnectionAdapters::ConnectionPool::ExecutorHooks")
                location = callback["source_location"]
                if callback["hook"] is None and location and location[0].endswith("/active_support/railtie.rb") and location[1] in (56, 60):
                    implemented = True
                if not implemented:
                    pending.append({"phase": phase, **callback})
        self.evidence["required_executor_callbacks_not_yet_proven"] = pending
        self.evidence["query_cache_request_lifecycle_parity"] = True
        self.evidence["context_and_queries_request_lifecycle_parity"] = True
        self.evidence["applicable_executor_lifecycle_parity"] = not pending

    def request_controls(self):
        assert self.evidence.get("complete_request_parity") is True
        reference = comparable({"requests": self.request_records("rails-oracle")})
        controls = []
        cors_negative_flags = []
        if self.evidence.get("cors_configuration_profile") == "enabled":
            cors_negative_flags = [("omitted-cors", "FIDELITY_STAGE4_OMIT_CORS"), ("wrong-cors-origin", "FIDELITY_STAGE4_WRONG_CORS_ORIGIN")]
        for runtime, argv in (("native", [self.path / "probe"]),
                ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
            for label, flag in (("omitted-route-callback", "FIDELITY_STAGE4_OMIT_ROUTE_CALLBACK"),
                                ("omitted-processing-middleware", "FIDELITY_STAGE4_OMIT_PROCESSING"),
                                ("omitted-host-authorization", "FIDELITY_STAGE4_OMIT_HOST_AUTHORIZATION"),
                                ("wrong-authorized-host-context", "FIDELITY_STAGE4_WRONG_AUTHORIZED_HOST"),
                                ("omitted-remote-ip", "FIDELITY_STAGE4_OMIT_REMOTE_IP"),
                                ("late-remote-ip", "FIDELITY_STAGE4_LATE_REMOTE_IP"),
                                ("wrong-remote-ip", "FIDELITY_STAGE4_WRONG_REMOTE_IP"),
                                ("omitted-request-id", "FIDELITY_STAGE4_OMIT_REQUEST_ID"),
                                ("late-request-id-context", "FIDELITY_STAGE4_LATE_REQUEST_ID"),
                                ("wrong-processing-order", "FIDELITY_STAGE4_WRONG_PROCESSING_ORDER"),
                                ("omitted-profiler-authorization", "FIDELITY_STAGE4_OMIT_PROFILER_AUTHORIZATION"),
                                ("wrong-crawler-predicate", "FIDELITY_STAGE4_WRONG_CRAWLER"),
                                ("wrong-theme", "FIDELITY_STAGE4_WRONG_THEME"),
                                ("omitted-preloader", "FIDELITY_STAGE4_OMIT_PRELOADER"),
                                ("omitted-snapshot-fields", "FIDELITY_STAGE4_OMIT_SNAPSHOT_FIELDS"),
                                ("wrong-snapshot-fields", "FIDELITY_STAGE4_WRONG_SNAPSHOT_FIELDS"),
                                ("wrong-readonly-state", "FIDELITY_STAGE4_WRONG_READONLY_STATE"),
                                ("omitted-locale", "FIDELITY_STAGE4_OMIT_LOCALE"),
                                ("wrong-locale-restore", "FIDELITY_STAGE4_WRONG_LOCALE_RESTORE"), *cors_negative_flags):
                name = f"{runtime}-stage4-{label}"
                self.env[flag] = "1"
                try:
                    code, _ = self.command(name, argv, cwd=ROOT / "discourse" if runtime == "compat" else ROOT, timeout=90,
                                           check=label != "omitted-locale")
                finally:
                    self.env.pop(flag, None)
                rows = self.request_records(name)
                if label == "omitted-locale":
                    # The existing supported-list locale guard correctly
                    # refuses French ambient state when the callback is skipped.
                    # Require the exact executed guard+cleanup, NOT any nonzero.
                    assert code != 0 and "unsupported list locale" in (self.path / (name + ".stderr")).read_text()
                    proof = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                             if line.startswith("FIDELITY_IGNORED_LOCALE_REFUSAL ")]
                    assert proof == [{"source_guard": "unsupported list locale", "context_cleanup": True, "ambient_locale": "fr"}]
                    assert not rows and not self.evidence["owned_cache_runtime_effects"][name]["effects"]
                    controls.append({"runtime": runtime, "control": label, "rejected_by_actual_list_locale_guard": True, "context_cleanup": True})
                    continue
                payload_status = lambda values: [{key: row[key] for key in ("path", "status", "body")} for row in values]
                if label != "omitted-locale":
                    equal_records(payload_status(self.request_records("rails-oracle")), payload_status(rows))
                if label == "omitted-route-callback":
                    assert all("x-discourse-route" not in {key.lower() for key in row["headers"]} for row in rows)
                elif label == "omitted-processing-middleware":
                    assert all(row["request_effects"]["processing_during_dispatch"] is None for row in rows)
                elif label == "omitted-host-authorization":
                    assert all(row["request_effects"]["authorized_host_during_dispatch"] is None for row in rows)
                elif label == "wrong-authorized-host-context":
                    assert all(row["request_effects"]["authorized_host_during_dispatch"] == "deliberately-wrong.invalid" for row in rows)
                elif label == "omitted-request-id":
                    assert all(row["request_effects"]["request_id_visible_and_consistent"] is False for row in rows)
                    assert all("x-request-id" not in {key.lower() for key in row["headers"]} for row in rows)
                elif label == "late-request-id-context":
                    assert all(row["request_effects"]["request_id_visible_and_consistent"] is False for row in rows)
                    assert all(re.fullmatch(r"[0-9a-f-]{36}", {key.lower(): value for key, value in row["headers"].items()}["x-request-id"]) for row in rows)
                elif label == "wrong-processing-order":
                    assert all(row["request_effects"]["processing_during_dispatch"] is True and row["request_effects"]["processing_during_profiler_save"] is None for row in rows)
                elif label == "omitted-profiler-authorization":
                    assert all(row["request_effects"]["profiler_authorized_after_dispatch"] is None for row in rows)
                elif label in ("omitted-remote-ip", "late-remote-ip"):
                    assert all(row["request_effects"]["remote_ip_during_dispatch"]["lazy_class"] is None for row in rows)
                elif label == "wrong-remote-ip":
                    assert all(row["request_effects"]["remote_ip_during_dispatch"]["value"] == "203.0.113.99" for row in rows)
                elif label == "wrong-crawler-predicate":
                    assert all({key.lower(): value for key, value in row["headers"].items()}.get("x-discourse-crawler-view") == "true" for row in rows)
                elif label == "wrong-theme":
                    assert all(row["request_effects"]["application_layout_preloader"]["theme_id"] == -987654 for row in rows)
                elif label == "omitted-preloader":
                    assert all(row["request_effects"]["application_layout_preloader"] == {"allocated": False} for row in rows)
                elif label == "omitted-snapshot-fields":
                    assert all(row["request_effects"]["profiler_snapshot_fields"] is None for row in rows)
                elif label == "wrong-snapshot-fields":
                    assert all(row["request_effects"]["profiler_snapshot_fields"]["Application version"] == "deliberately-wrong-test-version" for row in rows)
                elif label == "omitted-cors":
                    assert all(row["request_effects"]["cors_origins_during_dispatch"] is None for row in rows)
                    assert all("access-control-allow-origin" not in {key.lower() for key in row["headers"]} for row in rows)
                elif label == "wrong-cors-origin":
                    assert all(row["request_effects"]["cors_origins_during_dispatch"] for row in rows)
                    assert all({key.lower(): value for key, value in row["headers"].items()}["access-control-allow-origin"] == "https://wrong-test-origin.invalid" for row in rows)
                elif label == "wrong-readonly-state":
                    assert all(row["request_effects"]["readonly_state"]["readonly"] is True for row in rows)
                elif label == "omitted-locale":
                    assert all(row["request_effects"]["request_locale"]["during_callbacks"] == "fr" for row in rows)
                else:
                    assert all(row["request_effects"]["request_locale"]["after_dispatch"] == "en" for row in rows)
                try:
                    equal_records(reference, comparable({"requests": rows}))
                except AssertionError:
                    controls.append({"runtime": runtime, "control": label, "rejected": True})
                else:
                    raise AssertionError(f"ignored real callback/middleware accepted: {name}")
            name = f"{runtime}-stage4-unsupported-response-MIME"
            self.env["FIDELITY_STAGE4_UNSUPPORTED_MIME"] = "1"
            try:
                code, _ = self.command(name, argv, timeout=90, check=False)
            finally:
                self.env.pop("FIDELITY_STAGE4_UNSUPPORTED_MIME", None)
            assert code != 0 and "unsupported JSON profile HTML CSP" in (self.path / (name + ".stderr")).read_text()
            assert not self.request_records(name)
            assert not self.evidence["owned_cache_runtime_effects"][name]["effects"], "unsupported response executed profiler writes"
            controls.append({"runtime": runtime, "control": "unsupported-response-MIME", "actual_CSP_scope_guard_executed": True, "zero_profiler_writes": True})
            for profile in ("client-ip", "forwarded", "x-forwarded-for", "nil-forwarded", "proxy-host", "alternate-peer", "missing-peer", "method", "path", "conditional", "body", "prebound", "overload-client-ip", "query-override", "scheme-override", "script-override", "parameters-override", "server-name-override", "unknown-server"):
                name = f"{runtime}-stage4-ingress-{profile}"
                self.env["FIDELITY_STAGE4_INGRESS_PROFILE"] = profile
                try:
                    self.command(name, argv, timeout=90)
                finally:
                    self.env.pop("FIDELITY_STAGE4_INGRESS_PROFILE", None)
                proof = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (name + ".stdout")).read_text().splitlines() if line.startswith("FIDELITY_INGRESS_CONTROL ")]
                assert len(proof) == 1 and proof[0]["profile"] == profile and proof[0]["context_cleanup"] is True
                assert proof[0]["guard"].startswith("unsupported JSON ingress")
                assert not self.request_records(name)
                assert not self.evidence["owned_cache_runtime_effects"][name]["effects"], "unsupported ingress executed profiler writes"
                controls.append({"runtime": runtime, "control": "ingress-" + profile, "explicit_refusal_before_effects": True, "context_cleanup": True})
            for profile in ("api-key", "user-api-key", "authorization", "cookie", "preauthenticated", "query", "preauthenticated-api", "preauthenticated-user-api", "overload-api-key", "overload-cookie", "overload-preauthenticated-cookie"):
                name = f"{runtime}-stage4-credential-{profile}"
                self.env["FIDELITY_STAGE4_CREDENTIAL_PROFILE"] = profile
                try:
                    self.command(name, argv, cwd=ROOT / "discourse" if runtime == "compat" else ROOT, timeout=90)
                finally:
                    self.env.pop("FIDELITY_STAGE4_CREDENTIAL_PROFILE", None)
                output = (self.path / (name + ".stdout")).read_text()
                proof = [json.loads(line.split(" ", 1)[1]) for line in output.splitlines() if line.startswith("FIDELITY_CREDENTIAL_CONTROL ")]
                assert proof == [{"profile": profile, "refused": True, "context_cleanup": True}]
                assert not self.request_records(name) and "FIDELITY_JSON_REQUEST_MATERIALIZED" not in output
                assert not self.evidence["owned_cache_runtime_effects"][name]["effects"], "refused credential request wrote profiler data"
                controls.append({"runtime": runtime, "control": "credential-" + profile, "refused_before_request_data": True})
            for profile in ("required", "only-latest", "except-other"):
                self.env["FIDELITY_STAGE4_LOGIN_POLICY"] = profile
                name = f"{runtime}-stage4-login-policy-{profile}"
                try:
                    self.command(name, argv, cwd=ROOT / "discourse" if runtime == "compat" else ROOT, timeout=90)
                finally:
                    self.env.pop("FIDELITY_STAGE4_LOGIN_POLICY", None)
                rows = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                        if line.startswith("FIDELITY_LOGIN_POLICY_CONTROL ")]
                assert rows == [{"profile": profile, "denied": True, "context_cleanup": True}]
                assert not self.evidence["owned_cache_runtime_effects"][name]["effects"], "denied login profile wrote profiler cache"
                controls.append({"runtime": runtime, "control": "login-policy-" + profile, "denied_by_real_guard": True})
            self.env.update(FIDELITY_STAGE4_LOGIN_POLICY="required", FIDELITY_STAGE4_OMIT_LOGIN_GUARD="1")
            name = f"{runtime}-stage4-ignored-login-guard"
            try:
                self.command(name, argv, cwd=ROOT / "discourse" if runtime == "compat" else ROOT, timeout=90)
            finally:
                self.env.pop("FIDELITY_STAGE4_LOGIN_POLICY", None)
                self.env.pop("FIDELITY_STAGE4_OMIT_LOGIN_GUARD", None)
            rows = [json.loads(line.split(" ", 1)[1]) for line in (self.path / (name + ".stdout")).read_text().splitlines()
                    if line.startswith("FIDELITY_LOGIN_POLICY_CONTROL ")]
            assert rows == [{"profile": "required", "denied": False, "context_cleanup": True}], "missing login guard did not invalidate denial proof"
            assert self.evidence["owned_cache_runtime_effects"][name]["effects"], "ignored-guard control did not execute actual profiler writes"
            controls.append({"runtime": runtime, "control": "ignored-login-guard", "incorrect_acceptance_detected": True})
            name = f"{runtime}-readonly-omitted-header"
            self.env["FIDELITY_STAGE4_OMIT_READONLY_HEADER"] = "1"
            try:
                self.command(name, argv, cwd=ROOT / "discourse" if runtime == "compat" else ROOT, timeout=90)
            finally:
                self.env.pop("FIDELITY_STAGE4_OMIT_READONLY_HEADER", None)
            rows = self.readonly_records(name)
            assert len(rows) == 7
            assert any(row["request"]["request_effects"]["readonly_state"]["readonly"] is True for row in rows)
            assert all("discourse-readonly" not in {key.lower() for key in row["request"]["headers"]} for row in rows)
            try:
                comparable({"requests": self.request_records(name) + [row["request"] for row in rows]})
            except AssertionError:
                controls.append({"runtime": runtime, "control": "omitted-readonly-header", "rejected_under_real_readonly_flags": True})
            else:
                raise AssertionError("omitted readonly header accepted with real readonly mode")
            name = f"{runtime}-overload-ignored"
            self.env["FIDELITY_STAGE4_OMIT_OVERLOAD"] = "1"
            try:
                self.command(name, argv, cwd=ROOT / "discourse" if runtime == "compat" else ROOT, timeout=90)
            finally:
                self.env.pop("FIDELITY_STAGE4_OMIT_OVERLOAD", None)
            rows = self.overload_records(name)
            assert len(rows) == 2 and all(row["request"]["status"] == 200 and row["request"]["body"]["topic_list"]["topics"] for row in rows)
            assert self.evidence["owned_cache_runtime_effects"][name]["effects"], "ignored overload control did not enter real profiler"
            controls.append({"runtime": runtime, "control": "ignored-overload", "incorrect_200_under_real_queue_rejected": True})
        for runtime, argv in (("native", [self.path / "probe"]),
                ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
            for profile, updates, expected in (
                    ("invalid-enable-type", {"DISCOURSE_ENABLE_CORS": "not-a-boolean"}, "unsupported non-boolean CORS configuration"),
                    ("invalid-origin-type", {"DISCOURSE_ENABLE_CORS": "true", "DISCOURSE_CORS_ORIGIN": "123"}, "unsupported non-string global CORS origins")):
                prior = {key: self.env.get(key) for key in updates}
                self.env.update(updates)
                name = f"{runtime}-cors-{profile}"
                try:
                    code, _ = self.command(name, argv, check=False, timeout=90)
                finally:
                    for key, value in prior.items():
                        if value is None:
                            self.env.pop(key, None)
                        else:
                            self.env[key] = value
                assert code != 0 and expected in (self.path / (name + ".stderr")).read_text()
                assert not self.request_records(name)
                assert not self.evidence["owned_cache_runtime_effects"][name]["effects"], "unsupported CORS profile wrote profiler records"
                controls.append({"runtime": runtime, "control": "cors-" + profile, "exact_source_guard_rejected": True,
                                 "zero_profiler_writes": True})
        for runtime, argv in (("native", [self.path / "probe"]),
                ("compat", ["bundle", "exec", "ruby", self.path / "compat/entry.rb"])):
            for profile, flag in (("blocked", None), ("ignored-blocked", "FIDELITY_STAGE4_OMIT_HOST_AUTHORIZATION"),
                                  ("wrong-order", "FIDELITY_STAGE4_WRONG_HOST_ORDER")):
                self.env["FIDELITY_STAGE4_HOST_PROFILE"] = "blocked" if profile == "wrong-order" else profile
                if flag:
                    self.env[flag] = "1"
                name = f"{runtime}-host-{profile}"
                try:
                    code, _ = self.command(name, argv, check=False, timeout=90)
                finally:
                    self.env.pop("FIDELITY_STAGE4_HOST_PROFILE", None)
                    if flag:
                        self.env.pop(flag, None)
                lines = (self.path / (name + ".stdout")).read_text().splitlines()
                order = [json.loads(line.split(" ", 1)[1]) for line in lines if line.startswith("FIDELITY_BLOCKED_HOST_ORDER_PROOF ")]
                if profile == "wrong-order":
                    assert code != 0 and "blocked-host request ID ran before authorization" in (self.path / (name + ".stderr")).read_text()
                    assert len(order) == 1 and order[0] == {"request_id_assigned": True, "cors_entered": False,
                        "controller_entered": False, "blocked_hosts": ["attacker.invalid"], "context_cleanup": True}
                else:
                    assert code == 0
                    result = [json.loads(line.split(" ", 1)[1]) for line in lines if line.startswith("FIDELITY_HOST_CONTROL ")]
                    assert len(result) == 1 and result[0]["context_cleanup"] is True
                    if profile == "blocked":
                        assert result[0]["refused"] is True and result[0]["unsafe_200"] is False and result[0]["request"] is None
                        assert order == [{"request_id_assigned": False, "cors_entered": False,
                            "controller_entered": False, "blocked_hosts": ["attacker.invalid"], "context_cleanup": True}]
                    else:
                        assert result[0]["refused"] is False and result[0]["unsafe_200"] is True
                        unsafe = result[0]["request"]
                        assert unsafe["status"] == 200 and unsafe["body"]["topic_list"]["topics"]
                        assert unsafe["request_effects"]["authorized_host_during_dispatch"] is None
                        assert self.evidence["owned_cache_runtime_effects"][name]["effects"], "ignored host guard did not execute real profiler"
                assert not self.request_records(name)
                if profile != "ignored-blocked":
                    assert not self.evidence["owned_cache_runtime_effects"][name]["effects"]
                controls.append({"runtime": runtime, "control": "host-" + profile, "rejected_unsafe_or_unsupported_profile": True,
                                 "actual_order_and_context_cleanup_verified": True})
        original_host = [json.loads(line.split(" ", 1)[1]) for line in (self.path / "rails-oracle.stdout").read_text().splitlines()
                         if line.startswith("FIDELITY_HOST_REFERENCE ")]
        assert len(original_host) == 1 and original_host[0]["status"] == 403 and not original_host[0]["entered_callbacks"]
        assert original_host[0]["actual_middleware_env"] == {"blocked": ["attacker.invalid"], "authorized": None}
        self.evidence["original_blocked_host_reference"] = original_host
        original = [json.loads(line.split(" ", 1)[1]) for line in (self.path / "rails-oracle.stdout").read_text().splitlines()
                    if line.startswith("FIDELITY_CREDENTIAL_REFERENCE ")]
        assert len(original) == 2 and all(row["refused"] and 400 <= row["status"] < 500 for row in original)
        original_events = self.request_records("rails-oracle")[0]["profiler_proof"]["original_callback_events"]
        observed = [event["method"] for event in original_events if event["phase"] == "call"]
        projected = json.loads((self.path / "input/request-read-components.json").read_text())["projected_callback_declarations"]
        self.evidence["request_callback_inventory"] = {"original_actual_events": original_events,
            "projected_declarations_not_execution_coverage": projected,
            "remaining_original_targets": sorted(set(observed) - set(projected)),
            "all_original_callbacks_accepted": False}
        reference_proof = self.request_records("rails-oracle")[0]["profiler_proof"]
        self.command("response-middleware-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_response_middleware.py", "-v"], timeout=120)
        self.command("cors-middleware-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_cors_middleware.py", "-v"], timeout=120)
        self.evidence["cors_middleware_execution_controls"] = {
            "command": "cors-middleware-unit", "original_shared_native_header_algorithm_equal": True,
            "real_configuration_and_setting_store": True, "configuration_profile": self.evidence.get("cors_configuration_profile", "ambient"),
            "omission_and_wrong_origin_request_negatives_executed": bool(cors_negative_flags),
            "test_sources_sha256": {name: digest((HERE / "test" / name).read_bytes())
                for name in ("cors_middleware_matrix.rb", "test_cors_middleware.py")},
            "whole_stack_acceptance": False}
        response_classes = self.evidence["profiler_source_manifest"]["response_middleware"]["implemented_classes"]
        self.command("request-id-middleware-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_request_id_middleware.py", "-v"], timeout=120)
        self.command("host-authorization-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_host_authorization.py", "-v"], timeout=120)
        self.command("remote-ip-ingress-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_remote_ip_ingress.py", "-v"], timeout=180)
        self.evidence["remote_ip_ingress_execution_controls"] = {"original_shared_native_real_algorithm_equal": True,
            "singleton_range_rewrite_equivalent": True, "unsupported_ingress_refused_before_effects": True,
            "omission_wrong_and_late_context_rejected": True, "forwarded_profiles_accepted": False}
        self.evidence["host_authorization_execution_controls"] = {
            "command": "host-authorization-unit", "original_shared_native_permissions_scope_equal": True,
            "actual_IPv4_IPv6_and_live_development_host_configuration": True,
            "blocked_profile_and_ignored_guard_and_wrong_order_request_controls": True,
            "raw_original_403_retained_not_claimed_native_error_HTML": True,
            "test_sources_sha256": {name: digest((HERE / "test" / name).read_bytes())
                for name in ("host_authorization_matrix.rb", "test_host_authorization.py")},
            "whole_stack_acceptance": False}
        implemented_stack = ["Middleware::ProcessingRequest", "Middleware::OverloadProtections", "Rack::MiniProfiler", "ActionDispatch::HostAuthorization", "ActionDispatch::RequestId", "ActionDispatch::RemoteIp", *response_classes]
        self.command("json-profile-middleware-unit", ["python3", "-m", "unittest", "discover", "-s", HERE / "test",
            "-p", "test_json_profile_middleware.py", "-v"], timeout=180)
        scoped_classes = self.evidence["profiler_source_manifest"]["json_profile_middleware"]["supported_call_classes"]
        self.evidence["supported_json_middleware_applicability"] = {
            "classes": scoped_classes, "full_original_shared_native_call_paths_equal": True,
            "scope_exclusions_and_missing_guard_negatives_executed": True,
            "header_body_identity_and_original_fast_blank_controls": True,
            "unexpected_HTML_refuses_before_profiler_save": True,
            "full_optional_features_or_whole_stack_accepted": False}
        self.evidence["request_id_middleware_execution_controls"] = {
            "binding": "ActionDispatch::RequestId -> PortableDiscourseRequestIdMiddleware (actual fast_blank context)",
            "command": "request-id-middleware-unit", "real_request_env_before_controller": True,
            "original_shared_native_effects_equal": True, "omission_and_header_only_late_context_rejected": True,
            "test_sources_sha256": {name: digest((HERE / "test" / name).read_bytes())
                for name in ("request_id_middleware_matrix.rb", "test_request_id_middleware.py")},
            "whole_stack_acceptance": False}
        self.evidence["response_middleware_execution_controls"] = {
            "command": "response-middleware-unit", "original_shared_native_effects_equal": True,
            "real_placeholder_consumption_and_body_changes": True, "actual_fast_blank_not_AS_Unicode": True,
            "omitted_vary_track_and_nonce_rejected": True, "reversed_injector_order_rejected": True,
            "normal_JSON_response_has_no_placeholder_or_vary_flag": True,
            "test_sources_sha256": {name: digest((HERE / "test" / name).read_bytes())
                for name in ("response_middleware_matrix.rb", "test_response_middleware.py")},
            "whole_stack_acceptance": False}
        self.evidence["request_middleware_inventory"] = {
            "original_declared_stack": reference_proof["original_declared_middleware_stack"],
            "original_actual_call_return_events": reference_proof["original_middleware_events"],
            "implemented_stack_classes_not_whole_stack_acceptance": implemented_stack,
            "native_processing_scope_includes_actual_profiler_store": True,
            "framework_operations_not_whole_middleware_acceptance": {
                "Rack::ConditionalGet": "InProcessController calls actual response conditional finalizer",
                "ActionDispatch::Cookies": "actual framework CookieJar and session objects, incoming cookie profiles refuse"},
            "source_scoped_call_path_classes_not_full_optional_features": scoped_classes,
            "remaining_original_stack_entries": [name for name in reference_proof["original_declared_middleware_stack"] if name not in implemented_stack and name not in scoped_classes],
            "all_original_middleware_accepted": False}
        self.evidence["stage4_actual_callback_middleware_credential_controls"] = controls
        self.evidence["original_invalid_api_credentials"] = original
        self.evidence["all_original_callbacks_accepted"] = False
        self.save()


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--cruby-diagnostic", action="store_true", help="explicit diagnostic ONLY; cannot accept native request")
    parser.add_argument("--cors-configuration", choices=("ambient", "enabled"), default="ambient",
                        help="enabled: actual environment-provider CORS test configuration; no application methods/settings are forced")
    args = parser.parse_args()
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = LatestJsonRequestRun()
    run.evidence["cors_configuration_profile"] = args.cors_configuration
    if args.cors_configuration == "enabled":
        # Actual independently-read GlobalSetting EnvProvider inputs for the
        # TEST profile, not a production setter or a captured effective map.
        run.env.update(DISCOURSE_ENABLE_CORS="true",
                       DISCOURSE_CORS_ORIGIN="https://cors-a.invalid/, https://cors-b.invalid")
        run.evidence["cors_test_environment"] = {key: run.env[key] for key in ("DISCOURSE_ENABLE_CORS", "DISCOURSE_CORS_ORIGIN")}
    try:
        run.provenance()
        run.generate()
        if args.cruby_diagnostic:
            run.compat_diagnostic()
            run.evidence["status"] = "CRUBY_DIAGNOSTIC_ONLY_NOT_NATIVE_REQUEST_ACCEPTANCE"
            return
        run.oracle()
        run.run_partial()
        run.evidence["rails_parity"] = run.compare_oracle(run.records("rails-oracle"))
        run.stage1_controls()
        run.stage2_controls()
        run.latest_controls()
        run.list_controls()
        run.serialization_controls()
        run.compare_requests()
        run.request_controls()
        run.provenance()
        # Every observed callback target is now implemented for the supported
        # profile, but declaration inventory does not accept missing middleware.
        remaining = run.evidence["request_callback_inventory"]["remaining_original_targets"]
        assert not remaining, f"original callback targets remain: {remaining}"
        run.query_cache_lifecycle_controls()
        run.context_and_queries_controls()
        run.require_supported_request_lifecycle()
        pending = run.evidence["required_executor_callbacks_not_yet_proven"]
        targets = sorted({item["hook"] or str(item["source_location"]) for item in pending})
        if pending:
            raise RuntimeError("required original executor lifecycle/effects are not yet proven: " + ", ".join(targets))
        assert run.evidence["native_request_executed"] is True
        assert run.evidence["complete_request_parity"] is True
        assert len(run.evidence["context_and_queries_lifecycle_negative_controls"]) == 18
        run.evidence.update(status="PASS_SUPPORTED_CORE_NO_PLUGINS_NATIVE_JSON_REQUEST", json_request_accepted=True,
            stage_parity=True, stage4_json_request_accepted=True,
            stage_acceptance_scope="supported anonymous core/no-plugins JSON request only; not full query/options or page",
            all_supported_observed_callbacks_accepted=True,
            page_accepted=False, full_query_accepted=False, broader019_accepted=False,
            generic_executor_registry_accepted=False, full_optional_middleware_stack_accepted=False)
        run.evidence["actual_request_lifecycle_contracts"]["all_applicable_observed_executor_hooks_accepted"] = True
    except BaseException as error:
        run.evidence.update(status="FAILED_native_JSON_request_experiment", error=repr(error))
        raise
    finally:
        run.save()
        print(run.path)


if __name__ == "__main__":
    main()

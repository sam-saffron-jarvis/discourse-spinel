#!/usr/bin/env python3
"""PATCHED settings + original UNPRUNED anonymous security expression only.

Not full settings/native boot, member/admin matrix, TopicQuery or page acceptance.
No construction-context specialization removes the admin setting dependency.
"""
import json
import os
from pathlib import Path

from verify import Run, HERE, ROOT, digest, equal_records
from verify_topic_query import TopicQueryRun, ENTRY
from verify_anonymous_security import AnonymousSecurityRun


class PortableSecurityRun(AnonymousSecurityRun):
    def __init__(self):
        Run.__init__(self, "probe-portable-security")
        self.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", CARGO_INCREMENTAL="0", LOAD_PLUGINS="0")
        self.evidence.update(stage=__doc__, profile="PATCHED shared settings/unpruned anonymous security",
            broader019_accepted=False, core_latest_accepted=False, transformations=[])

    def emit_options(self):
        return []

    def validate_guardian(self, guardian):
        # Unlike the historical anonymous profile, keep the actual setting send.
        TopicQueryRun.validate_guardian(self, guardian)
        assert "requires a falsy predicate" not in guardian

    def generate(self):
        candidate = HERE / "compat/discourse/lib/site_settings"
        requires = "\n".join('require ' + json.dumps(str(candidate / name)) for name in (
            "portable_settings_context.rb", "portable_scalar_readers.rb", "portable_pg_provider.rb"))
        model = HERE / "compat/discourse/app/models/site_setting.rb"
        clauses = ["  extend SiteSettings::PortableSettingsContext", "  extend SiteSettings::PortableScalarReaders"]
        source = model.read_text()
        assert all(source.count(clause) == 1 for clause in clauses)
        # Source-equivalent explicit-receiver form of the two actual fixed
        # candidate mixins, after the declaration and before any consumer call.
        mixins = "\n".join("SiteSetting." + clause.strip() for clause in clauses)
        # Ruby's explicit-receiver call needs parentheses, not command syntax.
        mixins = mixins.replace(".extend ", ".extend(")
        mixins = "\n".join(line + ")" for line in mixins.splitlines())
        setup = f'''require "base64"
require_relative "emitted/runtime/rails"
require {json.dumps(str(ROOT / 'roundhouse/runtime/spinel/active_support_date_parsing.rb'))}
{requires}
{mixins}
settings_connection = Db.pool.conn(0).client
settings_site = settings_connection.exec("SELECT current_database()").getvalue(0, 0).to_s
settings_definitions = SiteSettings::PortableCoreDefinitions.build
settings_configuration = SiteSettings::PortableGlobalConfiguration.new(settings_definitions,
  {json.dumps(str(ROOT / 'discourse/config/discourse_defaults.conf'))},
  {json.dumps(str(ROOT / 'discourse/config/discourse.conf'))})
settings_provider = SiteSettings::PortablePgProvider.new({{settings_site => settings_connection}}, settings_configuration)
SiteSetting.configure_portable_settings(settings_provider, settings_site)
setting_value = SiteSetting.suppress_secured_categories_from_admin
puts "FIDELITY_PORTABLE_SECURITY_BOOT " + JSON.generate({{value: setting_value, ruby_class: setting_value.class.name}})
'''
        endpoint_guard = '''# TEST runner endpoint policy, before connection bootstrap.
raise "portable security PG endpoint guard" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
raise "portable security readonly policy" unless ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
'''
        entry = endpoint_guard + ENTRY.replace('require_relative "probe"', setup + '\nrequire_relative "probe"')
        (self.path / "entry.rb").write_text(entry)
        (self.path / "probe.rb").write_bytes((HERE / "test/topic_query_probe.rb").read_bytes())
        TopicQueryRun.generate(self)
        self.env["FIDELITY_EXTRA_ORIGINAL_INPUTS"] = json.dumps([
            "lib/topic_query.rb", "lib/guardian.rb", "lib/guardian/topic_guardian.rb",
            "lib/guardian/category_guardian.rb", "app/models/site_setting.rb", "lib/site_setting_extension.rb"])
        self.evidence["candidate_settings_manifest"] = json.loads((HERE / "compat/MANIFEST.json").read_text())
        self.evidence["source_mixin_transform"] = {"source": str(model), "sha256": digest(model.read_bytes()),
            "clauses": clauses, "explicit_receiver_form": mixins,
            "limitation": "partial declaration/bootstrap; original Rails special-setting implementation is NOT native"}
        self.evidence["construction_specialization"] = False

    def command(self, name, argv, **kwargs):
        if name == "native-compile":
            kwargs.setdefault("timeout", 180)
            argv = list(argv)
            argv[1:1] = ["--load-model=graph", "--no-inline-hot", "--cc=clang"]
        return super().command(name, argv, **kwargs)

    def run_partial(self):
        AnonymousSecurityRun.run_partial(self)
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

    def compare_oracle(self, oracle):
        if not (self.path / "native.stdout").exists():
            self.evidence["original_reference_first"] = True
            return {"reference_only": True, "native_equal": False}
        result = AnonymousSecurityRun.compare_oracle(self, oracle)
        result.update(scope="PATCHED shared settings plus ORIGINAL unpruned anonymous category-security expression ONLY",
                      construction_specialization=False, authenticated_admin_matrix_accepted=False,
                      native_full_site_setting_accepted=False, core_latest_accepted=False)
        return result

    def oracle_equivalence(self):
        if not (self.path / "native.stdout").exists():
            return "original guarded reference only; native equivalence NOT yet executed"
        return "patched shared settings + original unpruned anonymous expression match original Rails values/types/NULLs; not broader019 or page"

    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/portable_security_reference_consumer.rb", self.path / "probe.rb"]

    def provenance(self):
        # The historical anonymous specialization ledger is intentionally absent.
        TopicQueryRun.provenance(self)
        manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
        for name, expected in manifest["candidate_source_sha256"].items():
            assert digest((HERE / "compat" / name).read_bytes()) == expected, name
        if "candidate_settings_manifest" in self.evidence:
            assert manifest == self.evidence["candidate_settings_manifest"]
        runtime = ROOT / "roundhouse/runtime/spinel/active_support_date_parsing.rb"
        runtime_hash = digest(runtime.read_bytes())
        previous = self.evidence.get("additional_runtime_dependency")
        dependency = {"source": str(runtime.relative_to(ROOT)), "sha256": runtime_hash,
                      "reason": "stdlib JSON loads Date; existing SQL Date quote branch requires the actual Date formatter"}
        assert previous is None or previous == dependency
        self.evidence["additional_runtime_dependency"] = dependency
        self.evidence["boot_runtime_requires"] = ["base64", "emitted/runtime/rails"]


def boot_record(path):
    prefix = "FIDELITY_PORTABLE_SECURITY_BOOT "
    records = [json.loads(line[len(prefix):]) for line in path.read_text().splitlines() if line.startswith(prefix)]
    assert len(records) == 1
    return records[0]


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = PortableSecurityRun()
    try:
        run.provenance()
        run.generate()
        # Original guarded reference FIRST, before any native selected query.
        run.oracle()
        run.run_partial()
        for name in ("native", "compat"):
            expected, actual = boot_record(run.path / "rails-oracle.stdout"), boot_record(run.path / f"{name}.stdout")
            equal_records([expected["value"], expected["ruby_class"]], [actual["value"], actual["ruby_class"]])
        run.evidence["rails_parity"] = run.compare_oracle(run.records("rails-oracle"))
        run.provenance()
        run.evidence.update(status="patched_settings_unpruned_anonymous_expression_equal_ONLY", core_latest_accepted=False,
                            broader019_accepted=False)
    except Exception as error:
        run.evidence.update(status="failed_portable_security_integration", error=repr(error))
        raise
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()

#!/usr/bin/env python3
"""NEW patched/core-only shared settings read-store proof; old gates unchanged.

Not a patched Rails boot, full SiteSetting, query or page acceptance. All live
values come independently from readonly PG/configuration in each process.
"""
import copy
import json
import os
from pathlib import Path
import shutil

from probe_core_no_plugins import CoreNoPluginsRun
from verify import HERE, ROOT, digest, equal_records


class PortableSettingsRun(CoreNoPluginsRun):
    def oracle_arguments(self):
        return [HERE / "tools/core_no_plugins_oracle.rb", HERE / "tools/portable_settings_oracle_consumer.rb",
                self.path / "probe.rb"]


ENTRY = '''# frozen_string_literal: true
# TEST-only live consumer; the application store/provider/configuration below
# are the exact same tracked source in the CRuby and native processes.
require "pg"
require_relative "pg_driver"
require %s

# TEST consumer of the actual shared application modules; no replacement values
# or special-setting implementation. The provider/configuration remain real.
class PortableSettingsLiveAccessorConsumer
  include SiteSettings::PortableCoreReaders
  include SiteSettings::PortableScalarReaders
  attr_reader :portable_store, :portable_site
  def initialize(store, site)
    @portable_store = store
    @portable_site = site
  end
end

host = ENV.fetch("PGHOST")
port = ENV.fetch("PGPORT").to_i
database = ENV.fetch("PGDATABASE")
raise "portable PG endpoint guard" unless host == "127.0.0.1" && port == 5499 && database == "discourse_development"
connection = PgDriver.open(host, port, database, ENV.fetch("PGUSER"), ENV["PGPASSWORD"] || "")
begin
  connection.exec("SET default_transaction_read_only = on")
  state = connection.exec("SELECT current_database(), inet_server_port(), current_setting('default_transaction_read_only')")
  raise "portable PG session guard" unless state.getvalue(0, 0) == database && state.getvalue(0, 1) == "5499" && state.getvalue(0, 2) == "on"
  connection.exec("BEGIN READ ONLY")
  definitions = SiteSettings::PortableCoreDefinitions.build
  configuration = SiteSettings::PortableGlobalConfiguration.new(definitions,
    ENV.fetch("PORTABLE_REFERENCE_ROOT") + "/config/discourse_defaults.conf",
    ENV.fetch("PORTABLE_REFERENCE_ROOT") + "/config/discourse.conf")
  site = state.getvalue(0, 0).to_s
  provider = SiteSettings::PortablePgProvider.new({site => connection}, configuration)
  store = SiteSettings::PortableReadStore.new(definitions, provider)
  selected = PortableSettingsRecords.definitions_for_comparison(definitions)
  accessor_consumer = PortableSettingsLiveAccessorConsumer.new(store, site)
  records = PortableSettingsRecords.read_accessors(accessor_consumer, selected)
  raise "accessor/store parity failed" unless records == PortableSettingsRecords.read(store, selected, site)
  modified_count = selected.count { |definition| store.setting_modified_from_default?(definition.name, site) }
  raise "live provider override coverage missing" unless modified_count > 0
  before_title = accessor_consumer.title
  raise "scoped scalar accessor mismatch" unless accessor_consumer.title({theme_id: -1}) == before_title
  old_title = ENV["DISCOURSE_TITLE"]
  control_title = "portable live configuration control"
  callbacks = []
  begin
    ENV["DISCOURSE_TITLE"] = control_title
    raise "cache unexpectedly bypassed" unless accessor_consumer.title == before_title
    store.refresh!(site) do |changed_site, changes, removed|
      callbacks << [changed_site == site, changes.include?("title"), accessor_consumer.title == control_title]
    end
    raise "live config refresh failed" unless accessor_consumer.title == control_title && store.hidden?("title", site)
    raise "refresh callback failed" unless callbacks == [[true, true, true]]
  ensure
    old_title ? ENV["DISCOURSE_TITLE"] = old_title : ENV.delete("DISCOURSE_TITLE")
  end
  store.refresh!(site)
  raise "configuration restoration failed" unless accessor_consumer.title == before_title
  puts "FIDELITY_PORTABLE_SETTINGS " + JSON.generate({profile: "patched-core-no-plugins-shared-settings-read-store",
    definitions: definitions.length, compared: records.length, records: records,
    modified_count: modified_count, live_configuration_refresh: true, refresh_callbacks: callbacks,
    full_site_setting_accepted: false, core_latest_accepted: false})
ensure
  connection.exec("ROLLBACK")
  connection.close
end
'''


def record(path):
    prefix = "FIDELITY_PORTABLE_SETTINGS "
    rows = [json.loads(line.removeprefix(prefix)) for line in path.read_text().splitlines() if line.startswith(prefix)]
    assert len(rows) == 1
    return rows[0]


def main():
    os.sched_setaffinity(0, sorted(os.sched_getaffinity(0))[:4])
    run = PortableSettingsRun()
    run.env.update(CARGO_BUILD_JOBS="4", BUNDLE_JOBS="4", PORTABLE_REFERENCE_ROOT=str(ROOT / "discourse"))
    run.evidence.update(profile="patched-core-no-plugins-shared-settings-read-store",
                        stage="NEW shared application settings scalar read-store ONLY",
                        full_site_setting_accepted=False, core_latest_accepted=False,
                        native_values_from_oracle=False, native_build_profile={"jobs": 4, "inline_hot": False, "cc": "clang",
                          "reason": "default forced-hot-inline generated setjmp in get; documented no-inline profile retains semantics"})
    manifest = json.loads((HERE / "compat/MANIFEST.json").read_text())
    before = {name: digest((HERE / "compat" / name).read_bytes()) for name in manifest["candidate_source_sha256"]}
    assert before == manifest["candidate_source_sha256"]
    try:
        run.provenance()
        run.initial_reference()
        original = record(run.path / "rails-oracle.stdout")
        run.evidence["original_rails_and_shared_store"] = original
        entry = ENTRY % json.dumps(str(HERE / "test/portable_settings_records.rb"))
        for runtime, driver in (("cruby", "pg_driver_cruby.rb"), ("native", "pg_driver.rb")):
            out = run.path / runtime
            out.mkdir()
            (out / "entry.rb").write_text(entry)
            shutil.copyfile(ROOT / "roundhouse/runtime/spinel" / driver, out / "pg_driver.rb")
        run.command("shared-store-cruby", ["bundle", "exec", "ruby", run.path / "cruby/entry.rb"], timeout=120)
        cruby = record(run.path / "shared-store-cruby.stdout")
        pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
        binary = run.path / "native/settings"
        run.command("shared-store-native-compile", [ROOT / "spinel/bin/spinel", "--load-model=graph", "--jobs=4", "--no-inline-hot", "--cc=clang",
                    "-I", pg_dir, run.path / "native/entry.rb", "-o", binary], timeout=180)
        trace = run.path / "shared-accessors-native.trace"
        run.command("shared-store-native", ["strace", "-f", "-e", "trace=execve,connect", "-o", trace, binary], timeout=120)
        trace_text = trace.read_text()
        assert trace_text.count("execve(") == 1, "native settings spawned another process"
        connections = [line for line in trace_text.splitlines() if "connect(" in line]
        assert connections and all('sin_port=htons(5499)' in line and 'inet_addr("127.0.0.1")' in line for line in connections), "native settings used an unexpected endpoint"
        run.evidence["native_direct_pg_trace"] = {"path": str(trace), "execve_count": 1, "connections": connections}
        native = record(run.path / "shared-store-native.stdout")
        equal_records(original["records"], cruby["records"])
        equal_records(original["records"], native["records"])
        assert original["definitions"] == cruby["definitions"] == native["definitions"]
        assert original["compared"] == cruby["compared"] == native["compared"] > 0
        assert cruby["modified_count"] == native["modified_count"] > 0
        assert cruby["live_configuration_refresh"] and native["live_configuration_refresh"]
        equal_records(cruby["refresh_callbacks"], native["refresh_callbacks"])
        corrupted = copy.deepcopy(native["records"])
        corrupted[0][2] = ["deliberately incorrect checker value"]
        try:
            equal_records(original["records"], corrupted)
        except AssertionError:
            run.evidence["wrong_value_negative_detected"] = True
        else:
            raise AssertionError("comparison accepted a wrong setting")
        # Both entrypoints must refuse an unapproved endpoint BEFORE connect.
        for runtime, argv in (("cruby", ["bundle", "exec", "ruby", run.path / "cruby/entry.rb"]), ("native", [binary])):
            prior = run.env["PGPORT"]
            run.env["PGPORT"] = "6399"
            trace = run.path / f"{runtime}-wrong-endpoint.connect"
            try:
                code, _ = run.command(f"{runtime}-wrong-endpoint", ["strace", "-f", "-e", "trace=connect", "-o", trace, *argv], check=False, timeout=30)
            finally:
                run.env["PGPORT"] = prior
            assert code != 0 and "portable PG endpoint guard" in (run.path / f"{runtime}-wrong-endpoint.stderr").read_text()
            assert "connect(" not in trace.read_text(), "wrong endpoint reached a socket"
        assert before == {name: digest((HERE / "compat" / name).read_bytes()) for name in before}
        run.evidence.update(status="shared_scalar_store_original_CRuby_native_equal_ONLY", compared=original["compared"],
                            application_source_sha256=before, entry_sha256=digest(entry.encode()),
                            native_elf_sha256=digest(binary.read_bytes()), pg_source_sha256={
                                str(p.relative_to(pg_dir)): digest(p.read_bytes()) for p in sorted(pg_dir.rglob("*.rb"))},
                            endpoint_negatives_before_connect=True)
    finally:
        run.save()
        print(f"Evidence: {run.path}")


if __name__ == "__main__":
    main()

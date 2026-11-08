"""Native latest compile diagnostic plus emitted poster value-object unit.

Only the separately labelled unit executes. A refused whole-query compile never
produces executable query evidence, and a successful query build is still not
accepted or executed by this diagnostic.
"""
import json
from pathlib import Path
import os
import shutil

from verify import ROOT, HERE, digest, equal_records
from verify_topic_query import ENTRY


def poster_unit(run):
    """Actual strictly emitted candidate; labelled value-object unit, no DB."""
    probe = (HERE / "test/portable_topic_poster_probe.rb").read_text()
    entry = 'require_relative "emitted/app/models/topic_poster"\n' + probe
    path = run.path / "poster-unit-entry.rb"
    path.write_text(entry)
    binary = run.path / "poster-unit"
    code, _ = run.command("poster-unit-compile", [ROOT / "spinel/bin/spinel", "--load-model=graph",
        "--no-inline-hot", "--cc=clang", "--jobs=4", path, "-o", binary], check=False, timeout=90)
    assert code == 0, "actual emitted TopicPoster unit did not compile; output NOT executed"
    _, expected = run.command("poster-unit-cruby", ["ruby", path], timeout=30)
    _, actual = run.command("poster-unit-native", [binary], timeout=30)
    equal_records(expected, actual)
    assert actual.strip() == "FIDELITY_TOPIC_POSTER_UNIT app_fields_and_table_equal_ONLY"
    run.evidence["strict_inventory"].update(output_executed=True,
        executed_scope="TopicPoster value-object UNIT ONLY; full latest NOT executed")
    run.evidence["native_topic_poster_unit"] = {"equal": True, "entry_sha256": digest(entry.encode()),
        "query_rows_or_permissions": False, "full_openstruct_public_api_accepted": False}


def diagnose(run, emitted):
    target = run.path / "emitted"
    shutil.copytree(emitted, target)
    poster_unit(run)
    common = HERE / "compat/discourse/lib/site_settings"
    requires = "\n".join("require " + json.dumps(str(common / name)) for name in (
        "portable_core_readers.rb", "portable_settings_context.rb", "portable_scalar_readers.rb", "portable_pg_provider.rb"))
    setup = f'''require "base64"
require_relative "emitted/runtime/rails"
require {json.dumps(str(ROOT / 'roundhouse/runtime/spinel/active_support_date_parsing.rb'))}
{requires}
# Full actual shared reader modules; special getters retain explicit refusal.
# This diagnostic does NOT claim original Rails bootstrap was native.
SiteSetting.extend(SiteSettings::PortableCoreReaders)
SiteSetting.extend(SiteSettings::PortableSettingsContext)
SiteSetting.extend(SiteSettings::PortableScalarReaders)
connection = Db.pool.conn(0).client
site = connection.exec("SELECT current_database()").getvalue(0, 0).to_s
definitions = SiteSettings::PortableCoreDefinitions.build
configuration = SiteSettings::PortableGlobalConfiguration.new(definitions,
  {json.dumps(str(ROOT / 'discourse/config/discourse_defaults.conf'))},
  {json.dumps(str(ROOT / 'discourse/config/discourse.conf'))})
provider = SiteSettings::PortablePgProvider.new({{site => connection}}, configuration)
SiteSetting.configure_portable_settings(provider, site)
query = TopicQuery.new(nil, per_page: 20)
list = query.list_latest
rows = list.topics.map {{ |topic| [topic.id, topic.slug, topic.title, topic.category_id] }}
puts "FIDELITY_NATIVE_LATEST " + JSON.generate({{scope: "PATCHED latest-method diagnostic ONLY", rows: rows,
  core_latest_accepted: false}})
'''
    guard = '''raise "portable latest endpoint guard" unless ENV.fetch("DATABASE_URL") == "postgres://discourse@127.0.0.1:5499/discourse_development"
raise "portable latest readonly guard" unless ENV.fetch("PGOPTIONS").include?("default_transaction_read_only=on")
'''
    entry = guard + ENTRY.replace('require_relative "probe"', setup)
    entry_path = run.path / "native-latest-entry.rb"
    entry_path.write_text(entry)
    pg_dir = Path(os.environ.get("SPINEL_PG_DIR", str(Path.home() / ".cache/spin/packages/pg-0.2.0")))
    assert (pg_dir / "pg.rb").is_file()
    binary = run.path / "native-latest"
    code, _ = run.command("latest-native-compile", [ROOT / "spinel/bin/spinel", "--load-model=graph", "--no-inline-hot", "--cc=clang",
        "--jobs=4", "--rbs", target, "-I", pg_dir, entry_path, "-o", binary], check=False, timeout=360)
    run.evidence["native_latest_diagnostic"] = {"compile_returncode": code, "entry_sha256": digest(entry.encode()),
        "output_executed": False, "native_query_accepted": False, "core_latest_accepted": False,
        "additional_runtime_source_sha256": digest((ROOT / "roundhouse/runtime/spinel/active_support_date_parsing.rb").read_bytes())}
    return code

"""Complete core-only inputs for the FIRST observed /latest setting reader.

No plugin activation input, no synthetic SiteSetting, getters or values. This
candidate is compile-only until its original declaration/provider/refresh/boot
closure is admitted. Default YAML is original source, not an observed snapshot.
"""
import json
from pathlib import Path
import re
import subprocess

from verify import HERE, ROOT, PIN, digest

CODE = (
    "app/models/site_setting.rb", "lib/site_setting_extension.rb", "app/models/global_setting.rb",
    "lib/global_path.rb", "app/models/concerns/has_sanitizable_fields.rb",
    "lib/site_settings/deprecated_settings.rb", "lib/site_settings/defaults_provider.rb",
    "lib/site_settings/type_supervisor.rb", "lib/site_settings/validations.rb",
    "lib/site_settings/yaml_loader.rb", "lib/site_settings/db_provider.rb",
    "lib/site_settings/hidden_provider.rb", "lib/site_settings/dependency_graph.rb",
    "lib/site_settings/label_formatter.rb", "lib/enum.rb", "lib/upcoming_changes.rb",
    "lib/discourse_plugin_registry.rb", "app/models/theme_site_setting.rb",
)
RESOURCES = ("config/site_settings.yml", "config/discourse_defaults.conf")
BOOT = ("config/initializers/005-site_settings.rb",)


def materialize(output):
    output = Path(output)
    lock_path = HERE / "SOURCE_LOCK.json"
    lock = json.loads(lock_path.read_text())
    assert lock["discourse_revision"] == PIN
    existing = {item["path"]: item["sha256"] for item in lock["files"]}
    files = []
    for source in (*CODE, *RESOURCES, *BOOT):
        data = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{PIN}:{source}"])
        assert (ROOT / "discourse" / source).read_bytes() == data
        sha = digest(data)
        assert existing.get(source, sha) == sha
        copied = HERE / "source/discourse" / source
        if source not in existing:
            copied.parent.mkdir(parents=True, exist_ok=True)
            copied.write_bytes(data)
            lock["files"].append({"path": source, "sha256": sha})
        assert copied.read_bytes() == data
        target = "app/models/" + source.removeprefix("app/models/").removeprefix("lib/") if source in CODE else source
        destination = output / target
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(data)
        files.append({"source": source, "generated": target, "sha256": sha,
                      "bytes": len(data), "complete_original": True})
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    manifest = {"profile": "original-core-no-plugins", "first_observed_reader": "nested_replies_enabled",
                "declaration_resource": "config/site_settings.yml", "files": files,
                "scope": "compile-only FIRST core getter/declaration/provider/initializer candidate; NOT native bootstrap",
                "plugin_activation_included": False, "observed_values_used_as_inputs": False}
    (output / "core-getter-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest


def schema(run):
    tables = ("site_settings", "theme_site_settings", "site_setting_groups")
    assert all(re.fullmatch(r"[a-z_]+", table) for table in tables)
    script = '''require "pg"; require "json"
c = PG.connect(ENV.fetch("DATABASE_URL"))
begin
  raise "writable catalog" unless c.exec("SHOW default_transaction_read_only").getvalue(0,0) == "on"
  names = ARGV.map { |name| c.escape_literal(name) }.join(",")
  puts JSON.generate(c.exec("SELECT table_name,column_name,data_type,is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN (#{names}) ORDER BY table_name,ordinal_position").to_a)
ensure
  c.close
end
'''
    _, text = run.command("core-getter-catalog", ["bundle", "exec", "ruby", "-e", script, *tables], cwd=ROOT / "discourse", timeout=60)
    rows = json.loads(text)
    types = {"integer": "integer", "bigint": "bigint", "character varying": "string", "text": "text",
             "double precision": "float", "timestamp without time zone": "datetime", "boolean": "boolean", "jsonb": "jsonb"}
    lines = ["ActiveRecord::Schema.define do"]
    for table in tables:
        columns = [row for row in rows if row["table_name"] == table]
        assert columns and columns[0]["column_name"] == "id"
        lines.append(f'  create_table "{table}", id: :{types[columns[0]["data_type"]]} do |t|')
        for column in columns[1:]:
            lines.append(f'    t.{types[column["data_type"]]} "{column["column_name"]}", null: {str(column["is_nullable"] == "YES").lower()}')
        lines.append("  end")
    lines.append("end")
    run.evidence["core_getter_schema"] = {"catalog_rows": rows, "read_only_catalog_select_only": True,
                                          "no_production_setting_values": True}
    return "\n".join(lines) + "\n"

"""Readonly catalog-driven schema for explicitly partial latest model inputs."""
import json
import re

from verify import ROOT

TABLES = ("topics", "categories", "users", "groups", "tags", "topic_tags", "shared_drafts", "topic_users",
          "category_users", "tag_users", "dismissed_topic_users", "post_actions", "post_action_types", "posts", "flags",
          "tag_groups", "tag_group_memberships", "tag_group_permissions", "topic_timers", "topic_custom_fields")


def schema(run, tables=TABLES):
    assert all(re.fullmatch(r"[a-z_]+", name) for name in tables)
    script = '''require "pg"; require "json"
c = PG.connect(ENV.fetch("DATABASE_URL"))
begin
  raise "writable catalog" unless c.exec("SHOW default_transaction_read_only").getvalue(0,0) == "on"
  names = ARGV.map { |name| c.escape_literal(name) }.join(",")
  puts JSON.generate(c.exec("SELECT table_name,column_name,data_type,udt_name,is_nullable FROM information_schema.columns WHERE table_schema = 'public' AND table_name IN (#{names}) ORDER BY table_name,ordinal_position").to_a)
ensure
  c.close
end
'''
    _, output = run.command("latest-model-catalog", ["bundle", "exec", "ruby", "-e", script, *tables],
                            cwd=ROOT / "discourse", timeout=30)
    rows = json.loads(output)
    types = {"integer": "integer", "bigint": "bigint", "character varying": "string", "text": "text",
             "double precision": "float", "timestamp without time zone": "datetime", "boolean": "boolean",
             "jsonb": "jsonb", "date": "date", "inet": "inet"}
    lines = ["ActiveRecord::Schema.define do"]
    unsupported = []
    for table in tables:
        columns = [row for row in rows if row["table_name"] == table]
        assert columns, table
        identifier = next((row for row in columns if row["column_name"] == "id"), None)
        if identifier:
            lines.append(f'  create_table "{table}", id: :{types[identifier["data_type"]]} do |t|')
        else:
            lines.append(f'  create_table "{table}", id: false do |t|')
        for column in columns:
            if column is identifier:
                continue
            data_type = types.get(column["data_type"])
            array = column["data_type"] == "ARRAY"
            if array:
                data_type = {"_int4": "integer", "_int8": "bigint", "_text": "text", "_varchar": "string"}.get(column["udt_name"])
            if data_type is None:
                unsupported.append(column)
                continue
            options = ", array: true" if array else ""
            lines.append(f'    t.{data_type} "{column["column_name"]}", null: {str(column["is_nullable"] == "YES").lower()}{options}')
        lines.append("  end")
    lines.append("end")
    run.evidence["latest_model_catalog"] = {"rows": rows, "unsupported_columns": unsupported,
                                           "read_only_schema_metadata_only": True, "runtime_values_captured": False}
    assert not unsupported, f"unsupported actual catalog types: {unsupported}"
    return "\n".join(lines) + "\n"

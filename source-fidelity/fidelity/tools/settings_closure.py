"""Complete-file inputs for the bounded, NEVER EXECUTED settings diagnostic.

This is not a settings bootstrap or a replacement service. In particular,
config/application.rb and 005-site_settings.rb are audited boot inventory only:
the actual provider/plugin initialization and refresh effects remain unproved.
"""
from __future__ import annotations

import hashlib
from pathlib import Path
import shutil

CODE_INPUTS = (
    ("app/models/site_setting.rb", "app/models/site_setting.rb"),
    ("lib/site_setting_extension.rb", "app/models/site_setting_extension.rb"),
    ("app/models/global_setting.rb", "app/models/global_setting.rb"),
    ("lib/global_path.rb", "app/models/global_path.rb"),
    ("app/models/concerns/has_sanitizable_fields.rb", "app/models/concerns/has_sanitizable_fields.rb"),
    ("lib/site_settings/deprecated_settings.rb", "app/models/site_settings/deprecated_settings.rb"),
    ("lib/site_settings/defaults_provider.rb", "app/models/site_settings/defaults_provider.rb"),
    ("lib/site_settings/type_supervisor.rb", "app/models/site_settings/type_supervisor.rb"),
    ("lib/site_settings/yaml_loader.rb", "app/models/site_settings/yaml_loader.rb"),
    ("lib/site_settings/db_provider.rb", "app/models/site_settings/db_provider.rb"),
    ("lib/site_settings/hidden_provider.rb", "app/models/site_settings/hidden_provider.rb"),
    ("lib/site_settings/dependency_graph.rb", "app/models/site_settings/dependency_graph.rb"),
    ("lib/site_settings/label_formatter.rb", "app/models/site_settings/label_formatter.rb"),
    ("lib/enum.rb", "app/models/enum.rb"),
    ("lib/plugin.rb", "app/models/plugin.rb"),
    ("lib/plugin/instance.rb", "app/models/plugin/instance.rb"),
    ("lib/plugin/metadata.rb", "app/models/plugin/metadata.rb"),
    ("lib/discourse_plugin_registry.rb", "app/models/discourse_plugin_registry.rb"),
    ("lib/upcoming_changes.rb", "app/models/upcoming_changes.rb"),
    ("lib/discourse.rb", "app/models/discourse.rb"),
    ("app/models/theme_site_setting.rb", "app/models/theme_site_setting.rb"),
)
RESOURCE_INPUTS = (
    ("config/site_settings.yml", "config/site_settings.yml"),
    ("config/discourse_defaults.conf", "config/discourse_defaults.conf"),
    ("config/official_plugins.json", "config/official_plugins.json"),
)
BOOT_INVENTORY = ("config/application.rb", "config/initializers/005-site_settings.rb")


def digest(data: bytes) -> str:
    return hashlib.sha256(data).hexdigest()


def materialize(source: Path, output: Path) -> dict:
    files = []
    for role, inputs in (("complete_code", CODE_INPUTS), ("original_resource", RESOURCE_INPUTS)):
        for original, generated in inputs:
            data = (source / original).read_bytes()
            destination = output / generated
            destination.parent.mkdir(parents=True, exist_ok=True)
            shutil.copyfile(source / original, destination)
            files.append(dict(source=original, generated=generated, role=role,
                              sha256=digest(data), bytes=len(data)))
    inventory = [dict(source=path, sha256=digest((source / path).read_bytes())) for path in BOOT_INVENTORY]
    manifest = dict(files=files, boot_inventory_only=inventory, output_executed=False,
                    limitation="Complete-file diagnostic inputs ONLY. Provider/plugin bootstrap, native runtime declarations, original getter/cache/User/security execution remain unproved. Never execute output containing unsupported diagnostics.")
    audit(source, output, manifest)
    return manifest


def audit(source: Path, output: Path, manifest: dict) -> None:
    assert manifest["output_executed"] is False
    for item in manifest["files"]:
        original = (source / item["source"]).read_bytes()
        generated = (output / item["generated"]).read_bytes()
        assert generated == original, item["source"]
        assert digest(original) == item["sha256"], item["source"]
        assert len(original) == item["bytes"], item["source"]
    for item in manifest["boot_inventory_only"]:
        assert digest((source / item["source"]).read_bytes()) == item["sha256"]
        assert not (output / item["source"]).exists(), "boot inventory must not become a partial bootstrap"

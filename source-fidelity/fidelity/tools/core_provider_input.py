"""Measured core DbProvider dependencies; source-gem compiler context ONLY.

The current/site key calls RailsMultisite and the original provider reads DB.
Acquire their real source instead of inventing a DB facade, site name or types.
No package/body, Railtie effect, SQL, callback or runtime setting is substituted.
"""
import io
import json
from pathlib import Path
import re
import subprocess
import tarfile

from verify import HERE, ROOT, PIN, digest
from framework_sources import verify_framework_sources

PACKAGES = ("mini_sql", "rails_multisite")
CORE_FILES = (
    "lib/mini_sql_multisite_connection.rb", "config/initializers/000-mini_sql.rb",
    "lib/freedom_patches/rails_multisite.rb", "config/initializers/002-freedom_patches.rb",
)


def materialize(output):
    output = Path(output)
    lock_path = HERE / "SOURCE_LOCK.json"
    lock = json.loads(lock_path.read_text())
    assert lock["discourse_revision"] == PIN
    runtime_lock = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{PIN}:Gemfile.lock"])
    assert (ROOT / "discourse/Gemfile.lock").read_bytes() == runtime_lock
    core = []
    for source in CORE_FILES:
        content = subprocess.check_output(["git", "-C", str(ROOT / "discourse"), "show", f"{PIN}:{source}"])
        assert (ROOT / "discourse" / source).read_bytes() == content
        item = {"path": source, "sha256": digest(content)}
        prior = next((entry for entry in lock["files"] if entry["path"] == source), None)
        assert prior is None or prior == item
        copied = HERE / "source/discourse" / source
        if prior is None:
            copied.parent.mkdir(parents=True, exist_ok=True)
            copied.write_bytes(content)
            lock["files"].append(item)
        assert copied.read_bytes() == content
        generated = "app/models/mini_sql_multisite_connection.rb" if source == "lib/mini_sql_multisite_connection.rb" else source
        destination = output / generated
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_bytes(content)
        core.append({**item, "generated": generated, "complete_original": True})
    groups = []
    for gem in PACKAGES:
        versions = re.findall(rb"^    " + re.escape(gem.encode()) + rb" \(([0-9.]+)\)$", runtime_lock, re.M)
        assert len(versions) == 1, gem
        version = versions[0].decode()
        name = f"{gem}-{version}"
        package = ROOT / "run/bundle/ruby/4.0.0/cache" / (name + ".gem")
        subprocess.run(["ruby", "-rrubygems/package", "-e", 'raise "invalid gem" unless Gem::Package.new(ARGV.fetch(0)).verify', str(package)], check=True)
        package_bytes = package.read_bytes()
        with tarfile.open(fileobj=io.BytesIO(package_bytes), mode="r:*") as archive:
            data = archive.extractfile("data.tar.gz").read()
        files = []
        with tarfile.open(fileobj=io.BytesIO(data), mode="r:gz") as members:
            for member in members.getmembers():
                relative = Path(member.name)
                assert not relative.is_absolute() and ".." not in relative.parts
                if not member.isfile() or not ((member.name.startswith("lib/") and member.name.endswith(".rb")) or member.name.startswith(("LICENSE", "MIT-LICENSE"))):
                    continue
                content = members.extractfile(member).read()
                assert (ROOT / "run/bundle/ruby/4.0.0/gems" / name / relative).read_bytes() == content
                copied = Path("source/framework") / name / relative
                destination = HERE / copied
                if destination.exists():
                    assert destination.read_bytes() == content
                else:
                    destination.parent.mkdir(parents=True, exist_ok=True)
                    destination.write_bytes(content)
                generated = Path("vendor/bundle/ruby/4.0.0/gems") / name / relative
                destination = output / generated
                destination.parent.mkdir(parents=True, exist_ok=True)
                destination.write_bytes(content)
                files.append({"path": str(copied), "package_member": member.name, "sha256": digest(content)})
        assert files
        group = {"gem": gem, "version": version, "package": str(package.relative_to(ROOT)),
                 "package_sha256": digest(package_bytes), "runtime_lock": "discourse/Gemfile.lock",
                 "runtime_lock_sha256": digest(runtime_lock),
                 "verification": "Gem::Package.verify and complete lib/*.rb package-member/installed/copied equality; original license",
                 "files": files}
        prior = next((entry for entry in lock.setdefault("framework_sources", []) if entry["gem"] == gem), None)
        assert prior is None or prior == group
        if prior is None:
            lock["framework_sources"].append(group)
        groups.append(group)
    metadata = {
        "roundhouse.yml": "extensions:\n  - config/roundhouse\n",
        "config/roundhouse/gems.yml": "source_gems:\n" + "".join(f'  - {{gem: "{gem}"}}\n' for gem in PACKAGES),
        "config/application.rb": "Bundler.require(*Rails.groups)\n",
        "Gemfile": 'source "https://rubygems.org"\n' + "".join(f'gem "{gem}"\n' for gem in PACKAGES),
        ".bundle/config": '---\nBUNDLE_PATH: "vendor/bundle"\n',
    }
    for name, text in metadata.items():
        destination = output / name
        assert not destination.exists(), "do not overwrite original application context"
        destination.parent.mkdir(parents=True, exist_ok=True)
        destination.write_text(text)
    (output / "Gemfile.lock").write_bytes(runtime_lock)
    verify_framework_sources(lock, HERE, ROOT, digest)
    lock_path.write_text(json.dumps(lock, indent=2) + "\n")
    manifest = {"scope": "compile-only measured core provider source-gem candidate, NOT original full Rails boot or native execution",
                "complete_original_core_files": core, "complete_original_gem_sources": groups,
                "compiler_context_metadata_sha256": {name: digest((output / name).read_bytes()) for name in metadata},
                "original_runtime_lock_sha256": digest(runtime_lock), "plugin_sources_included": False,
                "railtie_body_replaced": False, "observed_values_or_sql_used_as_inputs": False,
                "multisite_patch_initializer_complete_original": True,
                "other_freedom_patch_glob_closure_admitted": False,
                "source_load_order_or_boot_admitted": False}
    (output / "core-provider-inputs.json").write_text(json.dumps(manifest, indent=2) + "\n")
    return manifest

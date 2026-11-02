#!/usr/bin/env python3
"""Stage the pinned discourse-details stylesheet through Discourse's Sass compiler.

Writes only minimal/build/assets/details-core/ after verifying the task-owned,
read-only Rails compiler environment. Run from the run root after harness/env.sh.
"""
from __future__ import annotations

import base64
import hashlib
import json
import os
from pathlib import Path
import subprocess

ROOT = Path(__file__).resolve().parents[2]
DISCOURSE = ROOT / "discourse"
PLUGIN = DISCOURSE / "plugins/discourse-details"
BUILD = ROOT / "minimal/build"
OUT = BUILD / "assets/details-core"
TEMP = BUILD / "assets/.details-core-stage-tmp"
REVISION = "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8"
SOURCE = PLUGIN / "assets/stylesheets/details.scss"
SETTINGS = PLUGIN / "config/settings.yml"
# Compiler.prepended_scss imports the original foundation variables/mixins;
# details.elided uses the latter's unselectable mixin. Hash these dependencies,
# not just the leaf plugin stylesheet, before any cached output is reused.
DEPENDENCIES = [DISCOURSE / path for path in (
    "plugins/discourse-details/plugin.rb",
    "lib/stylesheet/compiler.rb", "lib/stylesheet/importer.rb", "lib/asset_processor.rb",
    "app/assets/stylesheets/common/foundation/variables.scss",
    "app/assets/stylesheets/common/foundation/mixins.scss",
    "app/assets/stylesheets/common/foundation/math.scss",
    "app/assets/stylesheets/common/foundation/color_transformations.scss",
    "app/assets/stylesheets/lib/viewport.scss", "app/assets/stylesheets/lib/breakpoints.scss",
)]


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def fail(message: str) -> None:
    raise SystemExit(f"stage-details: {message}")


def verify_stage() -> bool:
    manifest_path = OUT / "manifest.json"
    if not manifest_path.is_file():
        return False
    try:
        manifest = json.loads(manifest_path.read_text())
        if manifest["format"] != 1 or manifest["stage_script_sha256"] != sha(Path(__file__)):
            fail("details stage format/script changed; explicit --regenerate required")
        if manifest["discourse_revision"] != REVISION:
            fail("details stage source revision changed")
        for row in manifest["source_files"]:
            source = ROOT / row["path"]
            if not source.is_file() or sha(source) != row["sha256"]:
                fail(f"details source changed or missing; explicit --regenerate required: {row['path']}")
        css = OUT / manifest["stylesheet"]["path"]
        if not css.is_file() or sha(css) != manifest["stylesheet"]["sha256"]:
            fail("staged details CSS failed manifest hash validation")
        cache = DISCOURSE / manifest["stylesheet"]["asset_processor_path"]
        if not cache.is_file() or sha(cache) != manifest["stylesheet"]["asset_processor_sha256"]:
            fail("cached AssetProcessor source changed; explicit --regenerate required")
        return True
    except (KeyError, TypeError, ValueError) as exc:
        fail(f"invalid details stage manifest: {exc}")


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regenerate", action="store_true", help="rebuild an owned stage")
    args = parser.parse_args()
    revision = subprocess.check_output(["git", "-C", str(DISCOURSE), "rev-parse", "HEAD"], text=True).strip()
    if revision != REVISION:
        fail(f"requires pinned Discourse revision {REVISION}, got {revision}")
    if OUT.exists() and not args.regenerate and verify_stage():
        print("Reused details stylesheet after verifying source, compiler cache and output hashes")
        return
    if TEMP.exists():
        fail(f"refusing to reuse temporary stage {TEMP.relative_to(ROOT)}")
    if OUT.exists() and not (OUT / "manifest.json").is_file():
        fail("refusing to replace unowned details output")
    if os.environ.get("DSPINEL_PG_URL") != "postgres://discourse@127.0.0.1:5499":
        fail("DSPINEL_PG_URL is not the task-owned PostgreSQL endpoint")
    if (os.environ.get("DISCOURSE_REDIS_HOST"), os.environ.get("DISCOURSE_REDIS_PORT")) != ("127.0.0.1", "6399"):
        fail("Discourse Redis environment is not the task-owned Valkey endpoint")
    pg = "postgres://discourse@127.0.0.1:5499/discourse_development"
    redis = "redis://127.0.0.1:6399/0"
    env = os.environ.copy()
    env.update({"DATABASE_URL": pg, "REDIS_URL": redis, "PGHOST": "127.0.0.1", "PGPORT": "5499", "PGUSER": "discourse", "PGDATABASE": "discourse_development", "PGOPTIONS": "-c default_transaction_read_only=on", "DISCOURSE_REDIS_HOST": "127.0.0.1", "DISCOURSE_REDIS_PORT": "6399"})
    identity = subprocess.run(["psql", pg, "-X", "-Atqc", "SELECT current_database() || '|' || current_user || '|' || inet_server_port() || '|' || current_setting('default_transaction_read_only')"], cwd=ROOT, env=env, text=True, capture_output=True, check=True, timeout=10).stdout.strip()
    if identity != "discourse_development|discourse|5499|on":
        fail(f"unsafe PostgreSQL identity: {identity}")
    server = subprocess.run(["redis-cli", "-u", redis, "INFO", "server"], cwd=ROOT, env=env, text=True, capture_output=True, check=True, timeout=8).stdout
    if dict(line.split(":", 1) for line in server.splitlines() if ":" in line).get("tcp_port") != "6399":
        fail("unsafe Valkey identity")
    ruby = r'''require "json"; require "base64"; abort("unexpected DATABASE_URL") unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"; bundle = AssetProcessor::BUNDLE; digest = bundle.send(:digest); path = bundle.path(digest); abort("missing exact-digest AssetProcessor bundle") unless File.file?(path); bytes = File.read(path); abort("stale AssetProcessor digest") unless digest == bundle.send(:digest); AssetProcessor.define_singleton_method(:load_or_build_processor_source) { bytes }; conn = ActiveRecord::Base.connection; css = nil; conn.transaction do; conn.execute("SET TRANSACTION READ ONLY"); row = conn.select_one("SELECT current_database() db,current_user usr,inet_server_port() port,current_setting('default_transaction_read_only') ro"); abort("wrong database identity: #{row}") unless row["db"] == "discourse_development" && row["usr"] == "discourse" && row["port"].to_i == 5499 && row["ro"] == "on"; css = Stylesheet::Compiler.compile_asset("discourse-details", theme_id: -1, color_scheme_id: ColorScheme.base.id).first; end; abort("AssetProcessor digest changed") unless digest == bundle.send(:digest); STDOUT.write(JSON.generate({css: Base64.strict_encode64(css), processor_digest: digest, processor_sha256: Digest::SHA256.hexdigest(bytes), processor_path: path}))'''
    result = subprocess.run(["bin/rails", "runner", ruby], cwd=DISCOURSE, env=env, text=True, capture_output=True, check=True, timeout=90)
    payload = json.loads(result.stdout)
    css = base64.b64decode(payload["css"], validate=True)
    TEMP.mkdir(parents=True)
    try:
        output = TEMP / "details.css"
        output.write_bytes(css)
        manifest = {"format": 1, "stage_script_sha256": sha(Path(__file__)), "discourse_revision": revision,
                    "source_plugin": "plugins/discourse-details", "source_files": [
                        {"path": str(path.relative_to(ROOT)), "sha256": sha(path)}
                        for path in [SOURCE, SETTINGS, *DEPENDENCIES]],
                    "stylesheet": {"path": "details.css", "sha256": sha(output),
                                   "compiler": "Stylesheet::Compiler.compile_asset('discourse-details', theme_id: -1)",
                                   "asset_processor_path": str(Path(payload["processor_path"]).relative_to(DISCOURSE)),
                                   "asset_processor_sha256": payload["processor_sha256"],
                                   "asset_processor_digest": payload["processor_digest"]}}
        (TEMP / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if OUT.exists():
            import shutil
            shutil.rmtree(OUT)
        TEMP.rename(OUT)
    except BaseException:
        import shutil
        shutil.rmtree(TEMP, ignore_errors=True)
        raise
    print(f"Staged original discourse-details Sass at {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    main()

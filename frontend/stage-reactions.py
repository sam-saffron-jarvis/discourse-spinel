#!/usr/bin/env python3
"""Build and hash the bounded read-only reactions plugin bundle using Discourse's compiler.

Run from the run root after sourcing harness/env.sh. Writes are confined to minimal/build/.
"""
from __future__ import annotations

import hashlib
import json
import os
import shutil
import subprocess
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
DISCOURSE = ROOT.parent / "discourse"
CORE_FRONTEND = DISCOURSE / "frontend/discourse"
PLUGIN = DISCOURSE / "plugins/discourse-reactions"
BUILD = ROOT / "build"
OUT = BUILD / "assets/reactions-core"
TEMP = BUILD / ".reactions-core-stage"
REVISION = subprocess.check_output(["git", "-C", str(DISCOURSE), "rev-parse", "HEAD"], text=True).strip()
if REVISION != "96ce8d44401a8a568ecc71561c26dca8ec6bfeb8":
    raise SystemExit("reactions stage requires the pinned Discourse revision")

SOURCES = {
    "components/discourse-reactions-counter.gjs": PLUGIN / "assets/javascripts/discourse/components/discourse-reactions-counter.gjs",
    "components/discourse-reactions-list.gjs": PLUGIN / "assets/javascripts/discourse/components/discourse-reactions-list.gjs",
    "components/discourse-reactions-list-emoji.gjs": PLUGIN / "assets/javascripts/discourse/components/discourse-reactions-list-emoji.gjs",
    "components/discourse-reactions-users-menu.gjs": PLUGIN / "assets/javascripts/discourse/components/discourse-reactions-users-menu.gjs",
    "components/discourse-reactions-actions-summary.gjs": PLUGIN / "assets/javascripts/discourse/components/discourse-reactions-actions-summary.gjs",
    "helpers/discourse-reactions-emoji.js": PLUGIN / "assets/javascripts/discourse/helpers/discourse-reactions-emoji.js",
    "models/discourse-reactions-custom-reaction.js": PLUGIN / "assets/javascripts/discourse/models/discourse-reactions-custom-reaction.js",
    "lib/hidden-post.js": PLUGIN / "assets/javascripts/discourse/lib/hidden-post.js",
    "upstream/discourse-reactions-actions.gjs": PLUGIN / "assets/javascripts/discourse/components/discourse-reactions-actions.gjs",
    "upstream/discourse-reactions-initializer.gjs": PLUGIN / "assets/javascripts/discourse/initializers/discourse-reactions.gjs",
    "upstream/users-popup.gjs": CORE_FRONTEND / "app/components/user/users-popup.gjs",
    "locale/client.en.yml": PLUGIN / "config/locales/client.en.yml",
    "stylesheets/common/discourse-reactions.scss": PLUGIN / "assets/stylesheets/common/discourse-reactions.scss",
    "stylesheets/desktop/discourse-reactions.scss": PLUGIN / "assets/stylesheets/desktop/discourse-reactions.scss",
    "stylesheets/mobile/discourse-reactions.scss": PLUGIN / "assets/stylesheets/mobile/discourse-reactions.scss",
}
LOCAL_ADAPTER = ROOT / "frontend/reactions/initializer-adapter.gjs"
LOCAL_ACTIONS = ROOT / "frontend/reactions/components/discourse-reactions-actions.gjs"


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def run(command: list[str], *, cwd: Path, env: dict[str, str] | None = None, timeout: int = 600) -> subprocess.CompletedProcess[str]:
    return subprocess.run(command, cwd=cwd, env=env, check=True, text=True, capture_output=True, timeout=timeout)


def compile_plugin_rollup(output_root: Path) -> dict:
    """Use the same cached AssetProcessor + Plugin::JsCompiler route as Discourse."""
    ruby = r'''require "json"; require "digest"; require "base64"; plugin_root = Rails.root.join("plugins/discourse-reactions/assets/javascripts"); modules = ["discourse/components/discourse-reactions-counter.gjs", "discourse/components/discourse-reactions-list.gjs", "discourse/components/discourse-reactions-list-emoji.gjs", "discourse/components/discourse-reactions-users-menu.gjs", "discourse/components/discourse-reactions-actions-summary.gjs", "discourse/helpers/discourse-reactions-emoji.js", "discourse/models/discourse-reactions-custom-reaction.js", "discourse/lib/hidden-post.js"]; tree = {}; modules.each { |relative| tree[relative] = File.read(plugin_root.join(relative)) }; tree["discourse/components/discourse-reactions-actions.gjs"] = File.read(ENV.fetch("REACTIONS_ACTIONS_ADAPTER")); tree["discourse/initializers/minimal-read-only-reactions.gjs"] = File.read(ENV.fetch("REACTIONS_INITIALIZER_ADAPTER")); entry_modules = ["discourse/initializers/minimal-read-only-reactions.gjs"]; entrypoints = {"main" => {"modules" => entry_modules}}; compiler = Plugin::JsCompiler.new("discourse-reactions", minify: true, tree: tree, entrypoints: entrypoints, filename_prefix: "discourse_reactions_", filename_suffix: "-read-only.digested", frontend_config: nil); chunks = compiler.compile!; chunks.each do |filename, info|; abort("plugin rollup returned compiler error") if info["code"].include?("Compile error:"); end; STDOUT.write(JSON.generate({"tree" => tree.keys.sort, "tree_sources" => tree.transform_values { |content| Digest::SHA256.hexdigest(content) }, "entrypoint_modules" => entry_modules, "chunks" => chunks.transform_values { |info| info.merge("code" => Base64.strict_encode64(info.fetch("code"))) }}))'''
    env = os.environ.copy()
    env["REACTIONS_ACTIONS_ADAPTER"] = str(LOCAL_ACTIONS)
    env["REACTIONS_INITIALIZER_ADAPTER"] = str(LOCAL_ADAPTER)
    pg_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
    env.update({"DATABASE_URL": pg_url, "REDIS_URL": "redis://127.0.0.1:6399/0", "PGHOST": "127.0.0.1", "PGPORT": "5499", "PGUSER": "discourse", "PGDATABASE": "discourse_development", "PGOPTIONS": "-c default_transaction_read_only=on", "DISCOURSE_REDIS_HOST": "127.0.0.1", "DISCOURSE_REDIS_PORT": "6399"})
    runner_env = env.copy()
    # Reuse only the exact prebuilt AssetProcessor source; this override prevents
    # AssetProcessor from creating/rebuilding cache files inside the source tree.
    script = r'''require "json"; require "digest"; bundle = AssetProcessor::BUNDLE; digest = bundle.send(:digest); path = bundle.path(digest); abort("missing exact-digest AssetProcessor bundle") unless File.file?(path); asset_processor_source = File.read(path); abort("stale AssetProcessor digest") unless digest == bundle.send(:digest); AssetProcessor.define_singleton_method(:load_or_build_processor_source) { asset_processor_source }; connection = ActiveRecord::Base.connection; connection.transaction { connection.execute("SET TRANSACTION READ ONLY"); row = connection.select_one("SELECT current_database() db,current_user usr,inet_server_port() port,current_setting('default_transaction_read_only') ro"); abort("unsafe DB identity #{row}") unless row["db"] == "discourse_development" && row["usr"] == "discourse" && row["port"].to_i == 5499 && row["ro"] == "on"; };
''' + ruby
    ident = run(["psql", pg_url, "-X", "-Atqc", "SELECT current_database() || '|' || current_user || '|' || inet_server_port() || '|' || current_setting('default_transaction_read_only')"], cwd=ROOT, env=runner_env, timeout=10).stdout.strip()
    if ident != "discourse_development|discourse|5499|on":
        raise SystemExit(f"unsafe plugin compile PostgreSQL identity: {ident}")
    redis = run(["redis-cli", "-u", "redis://discourse@127.0.0.1:6399/0", "INFO", "server"], cwd=ROOT, env=runner_env, timeout=8).stdout
    if dict(line.split(":", 1) for line in redis.splitlines() if ":" in line).get("tcp_port") != "6399":
        raise SystemExit("unsafe plugin compile Valkey identity")
    try:
        result = run(["bin/rails", "runner", script], cwd=DISCOURSE, env=runner_env, timeout=150)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"Plugin::JsCompiler failed: {error.stderr[-6000:]} {error.stdout[-2000:]}") from error
    payload = json.loads(result.stdout)
    output_dir = output_root / "js"
    output_dir.mkdir(parents=True, exist_ok=True)
    records = {}
    for filename, info in payload["chunks"].items():
        code = __import__("base64").b64decode(info.pop("code"), validate=True)
        target = output_dir / filename
        target.parent.mkdir(parents=True, exist_ok=True)
        target.write_bytes(code)
        output_path = f"js/{filename}"
        records[output_path] = {"sha256": sha(target), "bytes": len(code), "imports": [f"js/{item}" for item in info.get("imports", [])], "isEntry": info.get("isEntry", False), "name": info.get("name"), "modules": info.get("modules", [])}
    entrypoints = [path for path, row in records.items() if row["isEntry"]]
    if len(entrypoints) != 1:
        raise SystemExit(f"Plugin::JsCompiler expected one main entry chunk, got {entrypoints}")
    source_files = []
    for module_path, source_hash in payload["tree_sources"].items():
        if module_path == "discourse/components/discourse-reactions-actions.gjs":
            source_path = str(LOCAL_ACTIONS.relative_to(ROOT))
        elif module_path == "discourse/initializers/minimal-read-only-reactions.gjs":
            source_path = str(LOCAL_ADAPTER.relative_to(ROOT))
        else:
            source_path = str((PLUGIN / "assets/javascripts" / module_path).relative_to(DISCOURSE))
        source_files.append({"module": module_path, "path": source_path, "sha256": source_hash})
    return {"entrypoint": entrypoints[0], "chunks": {path: {"imports": row["imports"], "sha256": row["sha256"]} for path, row in records.items()}, "files": [{"path": path, "sha256": row["sha256"]} for path, row in records.items()], "compiler": "Plugin::JsCompiler -> AssetProcessor#rollup", "plugin_name": "discourse-reactions", "modules": payload["entrypoint_modules"], "source_modules": payload["tree"], "source_files": source_files}



def compile_scss(output_root: Path) -> dict:
    source = PLUGIN / "assets/stylesheets/common/discourse-reactions.scss"
    if os.environ.get("DSPINEL_PG_URL") != "postgres://discourse@127.0.0.1:5499":
        raise SystemExit("DSPINEL_PG_URL is not the task-owned PostgreSQL endpoint")
    if (os.environ.get("DISCOURSE_REDIS_HOST"), os.environ.get("DISCOURSE_REDIS_PORT")) != ("127.0.0.1", "6399"):
        raise SystemExit("Discourse Redis environment is not the task-owned Valkey endpoint")
    pg_url = "postgres://discourse@127.0.0.1:5499/discourse_development"
    redis_url = "redis://127.0.0.1:6399/0"
    env = os.environ.copy()
    env.update({"DATABASE_URL": pg_url, "REDIS_URL": redis_url, "PGHOST": "127.0.0.1", "PGPORT": "5499", "PGUSER": "discourse", "PGDATABASE": "discourse_development", "PGOPTIONS": "-c default_transaction_read_only=on", "DISCOURSE_REDIS_HOST": "127.0.0.1", "DISCOURSE_REDIS_PORT": "6399"})
    ident = run(["psql", pg_url, "-X", "-Atqc", "SELECT current_database() || '|' || current_user || '|' || inet_server_port() || '|' || current_setting('default_transaction_read_only')"], cwd=ROOT, env=env, timeout=10).stdout.strip()
    if ident != "discourse_development|discourse|5499|on":
        raise SystemExit(f"unsafe Rails/Sass compile database identity: {ident}")
    redis = run(["redis-cli", "-u", redis_url, "INFO", "server"], cwd=ROOT, env=env, timeout=8).stdout
    if dict(line.split(":", 1) for line in redis.splitlines() if ":" in line).get("tcp_port") != "6399":
        raise SystemExit("unsafe Rails/Sass compile Valkey identity")
    ruby = r'''require "json"; require "base64"; abort("unexpected DATABASE_URL") unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"; bundle = AssetProcessor::BUNDLE; digest = bundle.send(:digest); path = bundle.path(digest); abort("missing exact-digest AssetProcessor bundle") unless File.file?(path); bytes = File.read(path); abort("stale AssetProcessor digest") unless digest == bundle.send(:digest); AssetProcessor.define_singleton_method(:load_or_build_processor_source) { bytes }; conn = ActiveRecord::Base.connection; css = nil; conn.transaction do; conn.execute("SET TRANSACTION READ ONLY"); row = conn.select_one("SELECT current_database() db,current_user usr,inet_server_port() port,current_setting('default_transaction_read_only') ro"); abort("wrong database identity: #{row}") unless row["db"] == "discourse_development" && row["usr"] == "discourse" && row["port"].to_i == 5499 && row["ro"] == "on"; css = %w[discourse-reactions discourse-reactions_desktop discourse-reactions_mobile].map { |asset| Stylesheet::Compiler.compile_asset(asset, theme_id: -1, color_scheme_id: ColorScheme.base.id).first }.join("\n"); end; abort("AssetProcessor digest changed") unless digest == bundle.send(:digest); STDOUT.write(JSON.generate({css: Base64.strict_encode64(css), processor_digest: digest, processor_sha256: Digest::SHA256.hexdigest(bytes), processor_path: path}))'''
    try:
        result = run(["bin/rails", "runner", ruby], cwd=DISCOURSE, env=env, timeout=90)
    except subprocess.CalledProcessError as error:
        raise SystemExit(f"read-only plugin Sass compilation failed: {error.stderr[-4000:]}") from error
    payload = json.loads(result.stdout)
    css = __import__("base64").b64decode(payload["css"], validate=True)
    output = output_root / "stylesheets/discourse-reactions.css"
    output.parent.mkdir(parents=True, exist_ok=True)
    output.write_bytes(css)
    return {"source": str(source.relative_to(DISCOURSE)), "sha256": sha(source), "output": "stylesheets/discourse-reactions.css", "output_sha256": sha(output), "compiler": "Stylesheet::Compiler.compile_asset for discourse-reactions + _desktop + _mobile (original scoped rules)", "asset_processor_digest": payload["processor_digest"], "asset_processor_sha256": payload["processor_sha256"], "asset_processor_path": str(Path(payload["processor_path"]).relative_to(DISCOURSE)), "source_files": [{"path": str((PLUGIN / f"assets/stylesheets/{kind}/discourse-reactions.scss").relative_to(DISCOURSE)), "sha256": sha(PLUGIN / f"assets/stylesheets/{kind}/discourse-reactions.scss")} for kind in ("common", "desktop", "mobile")]}


def stage_sources(output_root: Path) -> dict:
    sources = {}
    for dest, source in SOURCES.items():
        target = output_root / dest
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        sources[dest] = {"source": str(source.relative_to(DISCOURSE)), "sha256": sha(source), "staged_sha256": sha(target)}
    adapter = output_root / "initializer-adapter.gjs"
    shutil.copyfile(LOCAL_ADAPTER, adapter)
    caller = output_root / "actions-caller-adapter.gjs"
    shutil.copyfile(LOCAL_ACTIONS, caller)
    return {"upstream": sources, "adapter": {"source": "frontend/reactions/initializer-adapter.gjs", "sha256": sha(LOCAL_ADAPTER), "staged_sha256": sha(adapter)}, "actions_caller_adapter": {"source": "frontend/reactions/components/discourse-reactions-actions.gjs", "sha256": sha(LOCAL_ACTIONS), "staged_sha256": sha(caller)}}


def verify_reusable_stage() -> bool:
    manifest_path = OUT / "manifest.json"
    if not manifest_path.is_file():
        return False
    try:
        manifest = json.loads(manifest_path.read_text())
        if manifest.get("format") != 3 or manifest.get("source_plugin") != "plugins/discourse-reactions":
            raise SystemExit("existing reactions stage is not a recognized format-3 output; explicit --regenerate required")
        if manifest.get("stage_script_sha256") != sha(Path(__file__)):
            raise SystemExit("reaction build adapter changed; explicit --regenerate required")
        if manifest.get("discourse_revision") != REVISION:
            raise SystemExit("pinned Discourse revision changed; explicit --regenerate required")
        for relative, row in manifest["sources"]["upstream"].items():
            source = DISCOURSE / row["source"]
            staged = OUT / relative
            if not source.is_file() or sha(source) != row["sha256"] or not staged.is_file() or sha(staged) != row["staged_sha256"]:
                raise SystemExit("upstream reaction input changed or staged source is corrupt; explicit --regenerate required")
        for key in ("adapter", "actions_caller_adapter"):
            row = manifest["sources"][key]
            source = ROOT / row["source"]
            staged = OUT / ("initializer-adapter.gjs" if key == "adapter" else "actions-caller-adapter.gjs")
            if not source.is_file() or sha(source) != row["sha256"] or not staged.is_file() or sha(staged) != row["staged_sha256"]:
                raise SystemExit(f"{key} changed or staged copy is corrupt; explicit --regenerate required")
        for row in manifest["javascript"]["files"]:
            target = OUT / row["path"]
            if not target.is_file() or sha(target) != row["sha256"]:
                raise SystemExit(f"compiled plugin JS failed hash verification: {row['path']}")
        css = manifest["stylesheet"]
        target = OUT / css["output"]
        if not target.is_file() or sha(target) != css["output_sha256"]:
            raise SystemExit("compiled plugin CSS failed hash verification")
        for row in manifest["javascript"]["source_files"]:
            base = ROOT if row["path"].startswith("frontend/") else DISCOURSE
            source = base / row["path"]
            if not source.is_file() or sha(source) != row["sha256"]:
                raise SystemExit(f"plugin JS input changed; explicit --regenerate required: {row['path']}")
        asset_processor = manifest["stylesheet" ]
        processor_path = DISCOURSE / asset_processor["asset_processor_path"]
        if not processor_path.is_file() or sha(processor_path) != asset_processor["asset_processor_sha256"]:
            raise SystemExit("cached AssetProcessor input changed; explicit --regenerate required")
        for row in asset_processor["source_files"]:
            source = DISCOURSE / row["path"]
            if not source.is_file() or sha(source) != row["sha256"]:
                raise SystemExit("plugin stylesheet input changed; explicit --regenerate required")
        return True
    except (KeyError, TypeError, ValueError, StopIteration) as error:
        raise SystemExit(f"invalid reactions stage manifest; explicit --regenerate required: {error}") from error


def main() -> None:
    import argparse
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--regenerate", action="store_true", help="explicitly rebuild after source or output changes")
    args = parser.parse_args()
    if TEMP.exists():
        raise SystemExit(f"refusing to reuse stage directory {TEMP}")
    if OUT.exists() and not args.regenerate:
        if verify_reusable_stage():
            print("Reused reaction bundle after verifying source, adapter, JS and CSS hashes")
            return
    if OUT.exists():
        manifest_path = OUT / "manifest.json"
        if not manifest_path.is_file():
            raise SystemExit(f"refusing to replace unowned output without manifest: {OUT}")
        old = json.loads(manifest_path.read_text())
        if old.get("source_plugin") != "plugins/discourse-reactions":
            raise SystemExit("refusing to replace output not created by this stage")
    TEMP.mkdir(parents=True)
    try:
        publish = TEMP / "publish"
        publish.mkdir()
        start = __import__("time").monotonic()
        source_hashes = stage_sources(publish)
        javascript = compile_plugin_rollup(publish)
        css = compile_scss(publish)
        duration = round(__import__("time").monotonic() - start, 3)
        manifest = {
            "format": 3,
            "stage_script_sha256": sha(Path(__file__)),
            "discourse_revision": REVISION,
            "source_plugin": "plugins/discourse-reactions",
            "sources": source_hashes,
            "required_site_settings": ["discourse_reactions_enabled", "discourse_reactions_enabled_reactions", "discourse_reactions_reaction_for_like", "discourse_reactions_like_icon", "discourse_reactions_desaturated_reaction_panel", "enable_emoji", "prioritize_username_in_ux"],
            "locale_source": {"path": "plugins/discourse-reactions/config/locales/client.en.yml", "sha256": sha(SOURCES["locale/client.en.yml"])},
            "stylesheet": css,
            "javascript": javascript,
            "entrypoint": {"loader": "loadPluginFromModulePreload", "plugin_name": "discourse-reactions", "module_registry_prefix": "discourse/plugins/discourse-reactions/", "module": javascript["entrypoint"]},
            "build_seconds": duration,
            "build_status": "compiled Plugin::JsCompiler/AssetProcessor#rollup plugin bundle and pinned common stylesheet",
        }
        (publish / "manifest.json").write_text(json.dumps(manifest, indent=2) + "\n")
        if OUT.exists():
            shutil.rmtree(OUT)
        OUT.parent.mkdir(parents=True, exist_ok=True)
        shutil.move(str(publish), str(OUT))
        print(f"Built actual Discourse plugin bundle at {OUT}; elapsed={duration}s")
    finally:
        shutil.rmtree(TEMP, ignore_errors=True)


if __name__ == "__main__":
    main()

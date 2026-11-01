#!/usr/bin/env python3
"""Stage pinned browser assets, reusing Ember JS and a read-only palette compiler.

Run from the run root after source harness/env.sh:
  python3 minimal/frontend/stage-assets.py
Only writes minimal/build/assets/native/. Existing generated output is hash-verified and safely replaced on rerun.
"""
from __future__ import annotations

import argparse
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import xml.etree.ElementTree as ET

ET.register_namespace("", "http://www.w3.org/2000/svg")

ROOT = Path(__file__).resolve().parents[2]
DISCOURSE = ROOT / "discourse"
BUILD = ROOT / "minimal" / "build"
OUTPUT = BUILD / "assets" / "native"
CORE = BUILD / "assets" / "discourse"
CACHE = DISCOURSE / "tmp" / "stylesheet-cache"


def fail(message: str) -> None:
    raise SystemExit(f"stage-assets: {message}")


def sha(path: Path) -> str:
    return hashlib.sha256(path.read_bytes()).hexdigest()


def copy_file(source: Path, target: Path) -> None:
    if not source.is_file():
        fail(f"required pinned source missing: {source.relative_to(ROOT)}")
    target.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(source, target)


def verify_existing_stage(strict_sources: bool = False) -> None:
    """Refuse to replace an unknown/corrupt directory; accept our intact stage on rerun."""
    manifest_path = OUTPUT / "manifest.json"
    if not manifest_path.is_file():
        fail(f"existing output is not a generated stage (missing manifest): {OUTPUT}")
    try:
        descriptor = json.loads(manifest_path.read_text(encoding="utf-8"))
        if descriptor.get("format") != 1:
            fail("existing stage manifest format is not recognized")
        entries: list[tuple[str, str]] = []
        source_entries: list[tuple[str, str]] = []
        for section in ("css", "browser_scripts", "images"):
            rows = list(descriptor[section].values())
            entries.extend((row["url"], row["sha256"]) for row in rows)
            source_entries.extend((row["source"], row.get("source_sha256", row["sha256"])) for row in rows if row.get("source"))
            for row in rows:
                source_entries.extend((source["path"], source["sha256"]) for source in row.get("source_files", []))
        entries.append((descriptor["locale"]["url"], descriptor["locale"]["sha256"]))
        locale = descriptor["locale"]
        source_entries.extend((locale[key], locale[hash_key]) for key, hash_key in (("source", "source_sha256"), ("date_source", "date_source_sha256")))
        entries.append((descriptor["icons"]["sprite_url"], descriptor["icons"]["sha256"]))
        entries.append((descriptor["service_worker"]["url"], descriptor["service_worker"]["sha256"]))
        entries.extend((row["url"], row["sha256"]) for row in descriptor["emoji"]["files"])
        entries.extend((row["url"], row["sha256"]) for row in descriptor["fonts"]["files"])
        entries.extend((row["url"], row["sha256"]) for row in descriptor["icons"]["files"])
        source_entries.extend((row["source"], row["sha256"]) for row in descriptor["icons"]["files"])
        source_entries.extend((row["source"], row["sha256"]) for row in descriptor["emoji"]["files"])
        source_entries.extend((row["source"], row["sha256"]) for row in descriptor["fonts"]["files"])
        source_entries.append((descriptor["service_worker"]["source"], descriptor["service_worker"]["source_sha256"]))
        for relative, expected in source_entries:
            source = ROOT / relative
            # Lane copies retain original source provenance. Only locked gem
            # inputs live outside this worktree; never fall back to shared
            # minimal/build output or create a mutable symlink to it.
            if relative.startswith("run/") and not source.is_file() and os.environ.get("DSPINEL_ROOT"):
                source = Path(os.environ["DSPINEL_ROOT"]) / relative
            if not source.is_file():
                fail(f"existing stage source is missing: {relative}")
            if sha(source) != expected:
                if strict_sources:
                    fail(f"staged asset source changed; explicit regeneration required: {relative}")
                print(f"Existing stage input changed; rebuilding from current source: {relative}", file=sys.stderr)
        for url, expected in entries:
            if url.startswith("/assets/native/"):
                path = OUTPUT / url.removeprefix("/assets/native/")
            elif url.startswith("/images/emoji/twitter/"):
                path = OUTPUT / "images" / url.removeprefix("/images/")
            elif url.startswith("/images/"):
                path = OUTPUT / "images" / url.removeprefix("/images/")
            elif url.startswith("/fonts/"):
                path = OUTPUT / "fonts" / url.removeprefix("/fonts/")
            elif url == "/service-worker.js":
                path = OUTPUT / "service-worker.js"
            else:
                fail(f"unrecognized staged asset URL in manifest: {url}")
            if not path.is_file() or sha(path) != expected:
                fail(f"existing staged asset failed manifest hash validation: {url}")
    except (KeyError, TypeError, ValueError) as exc:
        fail(f"existing stage manifest is invalid: {exc}")


def compile_foundation_palette() -> dict:
    """Compile pinned theme -1 CSS in a task-service-verified read-only runner."""
    expected_pg = "postgres://discourse@127.0.0.1:5499/discourse_development"
    expected_redis = "redis://127.0.0.1:6399/0"
    if os.environ.get("DSPINEL_PG_URL") != "postgres://discourse@127.0.0.1:5499":
        fail("DSPINEL_PG_URL is not the task-owned PostgreSQL endpoint")
    if (os.environ.get("DISCOURSE_REDIS_HOST"), os.environ.get("DISCOURSE_REDIS_PORT")) != ("127.0.0.1", "6399"):
        fail("Discourse Redis environment is not the task-owned Valkey endpoint")

    runner_env = os.environ.copy()
    runner_env.update({
        "DATABASE_URL": expected_pg,
        "REDIS_URL": expected_redis,
        "DSPINEL_PG_URL": "postgres://discourse@127.0.0.1:5499",
        "PGHOST": "127.0.0.1",
        "PGPORT": "5499",
        "PGUSER": "discourse",
        "PGDATABASE": "discourse_development",
        "PGOPTIONS": "-c default_transaction_read_only=on",
        "DISCOURSE_REDIS_HOST": "127.0.0.1",
        "DISCOURSE_REDIS_PORT": "6399",
    })
    pg_identity = subprocess.run(
        ["psql", expected_pg, "-X", "-Atqc", "SELECT current_database() || '|' || current_user || '|' || inet_server_port() || '|' || current_setting('default_transaction_read_only')"],
        check=True, text=True, capture_output=True, timeout=8, env=runner_env,
    ).stdout.strip()
    if pg_identity != "discourse_development|discourse|5499|on":
        fail(f"refusing Rails palette compile on unexpected/read-write PostgreSQL identity: {pg_identity}")
    redis_info = subprocess.run(
        ["redis-cli", "-u", expected_redis, "INFO", "server"],
        check=True, text=True, capture_output=True, timeout=5, env=runner_env,
    ).stdout
    redis_identity = dict(line.split(":", 1) for line in redis_info.splitlines() if ":" in line)
    if redis_identity.get("tcp_port") != "6399":
        fail("refusing Rails palette compile without task-owned Valkey identity")

    ruby = r'''require "json"; require "base64"; abort("unexpected DATABASE_URL") unless ENV["DATABASE_URL"] == "postgres://discourse@127.0.0.1:5499/discourse_development"; abort("unexpected REDIS_URL") unless ENV["REDIS_URL"] == "redis://127.0.0.1:6399/0"; bundle = AssetProcessor::BUNDLE; source_digest = bundle.send(:digest); bundle_path = bundle.path(source_digest); abort("missing exact-digest AssetProcessor cache; refusing any build") unless File.file?(bundle_path); bundle_source = File.read(bundle_path); bundle_sha256 = Digest::SHA256.hexdigest(bundle_source); abort("AssetProcessor digest changed during source check") unless source_digest == bundle.send(:digest); AssetProcessor.define_singleton_method(:load_or_build_processor_source) { bundle_source }; connection = ActiveRecord::Base.connection; result = nil; connection.transaction do; connection.execute("SET TRANSACTION READ ONLY"); identity = connection.select_one("SELECT current_database() AS db, current_user AS usr, inet_server_port() AS port, current_setting('default_transaction_read_only') AS read_only"); abort("unexpected/read-write Rails PostgreSQL identity: #{identity}") unless identity["db"] == "discourse_development" && identity["usr"] == "discourse" && identity["port"].to_i == 5499 && identity["read_only"] == "on"; scheme = ColorScheme.base; css, = Stylesheet::Compiler.compile_asset(:color_definitions, theme_id: -1, color_scheme_id: scheme.id, load_paths: nil); font_names = css.scan(%r{/fonts/([^?\")]+)}).flatten.uniq; result = {"css" => Base64.strict_encode64(css), "theme_id" => -1, "color_scheme_id" => scheme.id, "color_scheme_name" => scheme.name, "font_root" => DiscourseFonts.path_for_fonts, "font_files" => font_names, "asset_processor_digest" => source_digest, "asset_processor_path" => bundle_path, "asset_processor_sha256" => bundle_sha256}; end; abort("AssetProcessor source digest changed during compile") unless source_digest == bundle.send(:digest); STDOUT.write(JSON.generate(result))'''
    result = subprocess.run(
        ["bin/rails", "runner", ruby], cwd=DISCOURSE, check=True, text=True,
        capture_output=True, timeout=60, env=runner_env,
    )
    try:
        payload = json.loads(result.stdout)
    except json.JSONDecodeError as exc:
        fail(f"isolated Rails color compilation did not return its JSON descriptor: {exc}; stderr={result.stderr[-1000:]}")
    return payload


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--reuse", action="store_true", help="reuse an existing stage only after verifying all staged bytes and source hashes")
    args = parser.parse_args()
    if OUTPUT.exists():
        verify_existing_stage(strict_sources=args.reuse)
        if args.reuse:
            print("Reused this worktree's staged assets after verifying every staged byte and source hash")
            return
    temporary = OUTPUT.with_name(".native-stage-tmp")
    if temporary.exists():
        fail(f"refusing to reuse temporary stage: {temporary.relative_to(ROOT)}")
    manifest_path = CORE / "manifest" / "manifest.json"
    if not manifest_path.is_file():
        fail("existing core Ember manifest is missing; run build-ember-assets.sh explicitly first")
    if not CACHE.is_dir():
        fail("pinned Discourse stylesheet cache missing; will not invoke Rails/precompile")

    # The only reusable unthemed output is core common.css. Cached theme outputs
    # belong to Horizon (theme -2), while the default Foundation theme is -1.
    # Never attach Horizon CSS to a Foundation document.
    css_sources = {"common.css": sorted(CACHE.glob("common_[0-9a-f]*.css"))}
    for label, candidates in css_sources.items():
        if not candidates:
            fail(f"no actual cached {label} output under discourse/tmp/stylesheet-cache")

    temporary.mkdir(parents=True)
    try:
        css_manifest: dict[str, dict[str, str]] = {}
        for logical, candidates in css_sources.items():
            source = candidates[-1]
            target = temporary / "css" / logical
            copy_file(source, target)
            # Cached CSS was generated for localhost/root. Rebase its public
            # image references relative to this stylesheet, not to any listener
            # or widget mount, exactly as with staged palette/font URLs below.
            css = target.read_text(encoding="utf-8")
            css = css.replace('url("http://localhost:3000/images/', 'url("../images/')
            css = css.replace('url("/images/', 'url("../images/')
            target.write_text(css, encoding="utf-8")
            css_manifest[logical] = {
                "url": f"/assets/native/css/{logical}",
                "source": str(source.relative_to(ROOT)),
                "source_sha256": sha(source),
                "sha256": sha(target),
                "adaptation": "Root/reference-host public image URLs rebased relative to staged CSS for any mount prefix.",
            }

        palette = compile_foundation_palette()
        palette_css = base64.b64decode(palette["css"], validate=True).decode("utf-8")
        def rebase_font_url(match):
            quote, relative = match.group(1), match.group(2)
            return f"url({quote}fonts/{relative}{quote})"

        palette_css = re.sub(
            r"""url\((['\"])(?:https?:)?//[^/]+/fonts/([^'\"]+)\1\)""",
            rebase_font_url,
            palette_css,
        )
        palette_css = re.sub(
            r"""url\((['\"])/fonts/([^'\"]+)\1\)""",
            rebase_font_url,
            palette_css,
        )
        for name in palette["font_files"]:
            if Path(name).name != name:
                fail(f"unsafe pinned font filename from Sass output: {name}")
            font_source = Path(palette["font_root"]) / name
            font_target = temporary / "css" / "fonts" / name
            copy_file(font_source, font_target)
        palette_output = temporary / "css" / "color-definitions.css"
        palette_output.write_text(palette_css, encoding="utf-8")
        palette_sources = [
            "lib/stylesheet/compiler.rb", "lib/stylesheet/importer.rb", "lib/stylesheet/manager.rb",
            "lib/stylesheet/manager/builder.rb", "lib/asset_processor.rb", "lib/precompiled_bundle.rb",
            "app/assets/stylesheets/color_definitions.scss", "app/assets/stylesheets/wcag.scss",
            "app/models/color_scheme.rb", "lib/letter_avatar.rb",
        ]
        palette_source_rows = [
            {"path": str((DISCOURSE / rel).relative_to(ROOT)), "sha256": sha(DISCOURSE / rel)}
            for rel in palette_sources
        ]
        css_manifest["color-definitions.css"] = {
            "url": "/assets/native/css/color-definitions.css",
            "sha256": sha(palette_output),
            "source_files": palette_source_rows,
            "asset_processor_digest": palette["asset_processor_digest"],
            "asset_processor_sha256": palette["asset_processor_sha256"],
            "color_scheme_id": palette["color_scheme_id"],
        }
        fonts = []
        for name in palette["font_files"]:
            source = Path(palette["font_root"]) / name
            fonts.append({
                "url": f"/assets/native/css/fonts/{name}",
                "source": str(source.relative_to(ROOT)),
                "sha256": sha(source),
                "discourse_url": f"/fonts/{name}",
            })

        # Generate the English client bundle from pinned source locales. The pinned helper
        # also emits a MessageFormat bundle as a separate endpoint; this isolated stage
        # omits that plugin/Rails compiler output but supplies its function contract so
        # core I18n can initialize and reports the limitation in the descriptor.
        locale_source = DISCOURSE / "config" / "locales" / "client.en.yml"
        date_source = DISCOURSE / "config" / "locales" / "server.en.yml"
        locale_output = temporary / "locale" / "en.js"
        locale_output.parent.mkdir(parents=True, exist_ok=True)
        ruby = r'''require "yaml"; require "json"; client = YAML.load_file(ARGV.fetch(0), aliases: true).fetch("en"); js = client.fetch("js"); formats = YAML.load_file(ARGV.fetch(1), aliases: true).fetch("en").fetch("dates"); puts JSON.generate({"translations" => {"en" => {"js" => js}}, "formats" => formats.slice("short_date_no_year", "short_date", "long_date")})'''
        result = subprocess.run(["ruby", "-e", ruby, str(locale_source), str(date_source)], check=True, text=True, capture_output=True)
        locale_data = json.loads(result.stdout)

        def without_message_formats(value):
            if isinstance(value, dict):
                return {key: without_message_formats(child) for key, child in value.items() if not key.endswith("_MF")}
            if isinstance(value, list):
                return [without_message_formats(child) for child in value]
            return value

        locale_data["translations"] = without_message_formats(locale_data["translations"])
        locale_js = "\n".join([
            "(() => {",
            "  const data = " + json.dumps(locale_data, ensure_ascii=False, separators=(",", ":")) + ";",
            "  const localeData = window._discourse_locale_data ??= {};",
            "  localeData.translations = data.translations;",
            "  localeData.locale = 'en';",
            "  localeData.messageFormatData = () => ({});",
            "  localeData.configureMoment = function() {",
            "    if (!globalThis.moment) throw new Error('globalThis.moment not defined. Failed to initialize locales.');",
            "    const moment = globalThis.moment;",
            "    if (moment.localeData().postformat('0') !== '0') moment.updateLocale(moment.locale(), { postformat: (string) => string });",
            "    moment.fn.shortDateNoYear = function() { return this.format(data.formats.short_date_no_year); };",
            "    moment.fn.shortDate = function() { return this.format(data.formats.short_date); };",
            "    moment.fn.longDate = function() { return this.format(data.formats.long_date); };",
            "    moment.fn.relativeAge = function(opts) { return Discourse.Formatter.relativeAge(this.toDate(), opts); };",
            "  };",
            "})();",
            "",
        ])
        locale_output.write_text(locale_js, encoding="utf-8")

        # Browser support scripts are served by Rails' asset pipeline in production,
        # separately from Rolldown's import-map manifest.
        browser_scripts = {}
        for script_name in ("browser-detect", "browser-update"):
            source = DISCOURSE / "frontend" / "discourse" / "scripts" / "js" / f"{script_name}.js"
            target = temporary / "js" / f"{script_name}.js"
            copy_file(source, target)
            browser_scripts[script_name] = {
                "url": f"/assets/native/js/{script_name}.js",
                "source": str(source.relative_to(ROOT)),
                "sha256": sha(source),
            }

        # Copy original public image files, not screenshots or rendered output.
        image_sources = [
            "avatar.png", "default-favicon.png", "default-favicon.ico", "firenoise.png",
            "d-logo-sketch.png", "d-logo-sketch-small.png",
            "discourse-logo-sketch-small.png",
        ]
        images: dict[str, dict[str, str]] = {}
        for name in image_sources:
            source = DISCOURSE / "public" / "images" / name
            target = temporary / "images" / name
            copy_file(source, target)
            images[name] = {"url": f"/images/{name}", "source": str(source.relative_to(ROOT)), "sha256": sha(source)}

        # Preserve the pinned source SVG icon inputs as a complete static icon source
        # tree. These are the same vendor SVGs consumed by SvgSprite.core_svgs.
        svg_root = DISCOURSE / "vendor" / "assets" / "svg-icons"
        svg_files = sorted(svg_root.rglob("*.svg"))
        if not svg_files:
            fail("no pinned vendor SVG icon sources found")
        icon_files = []
        for source in svg_files:
            relative = source.relative_to(svg_root)
            target = temporary / "icons" / relative
            copy_file(source, target)
            icon_files.append({
                "url": f"/assets/native/icons/{relative.as_posix()}",
                "source": str(source.relative_to(ROOT)),
                "sha256": sha(source),
            })

        # Deliver a sprite using actual source <symbol> nodes; runtime path/version
        # remains supplied by the native setup data and can point at this endpoint.
        symbols: list[str] = []
        for source in svg_files:
            try:
                tree = ET.parse(source)
            except ET.ParseError as error:
                fail(f"invalid pinned SVG source {source.relative_to(ROOT)}: {error}")
            family = source.stem
            for elem in tree.iter():
                if elem.tag.rsplit("}", 1)[-1] != "symbol":
                    continue
                icon_id = elem.attrib.get("id", "")
                if family == "regular":
                    elem.attrib["id"] = "far-" + icon_id
                elif family == "brands":
                    elem.attrib["id"] = "fab-" + icon_id
                elem.attrib["overflow"] = "visible"
                for title in [child for child in elem.iter() if child.tag.rsplit("}", 1)[-1] == "title"]:
                    parent = next((node for node in elem.iter() if title in list(node)), None)
                    if parent is not None:
                        parent.remove(title)
                symbols.append(ET.tostring(elem, encoding="unicode"))
        sprite = "<svg xmlns='http://www.w3.org/2000/svg' style='display:none'>" + "".join(symbols) + "</svg>"
        parsed_sprite = ET.fromstring(sprite)
        symbol_tag = "{http://www.w3.org/2000/svg}symbol"
        symbol_ids = {element.attrib.get("id") for element in parsed_sprite.findall(".//" + symbol_tag)}
        if not {"bars", "far-calendar-check", "fab-github"}.issubset(symbol_ids):
            fail("generated core sprite is missing expected regular/brand/solid symbol ids")
        if "ns0:" in sprite or "xmlns:ns" in sprite:
            fail("generated sprite contains serialized namespace prefixes, not HTML SVG tags")
        sprite_js = "window.__svg_sprite = " + json.dumps(sprite, ensure_ascii=False) + ";\n"
        sprite_path = temporary / "icons" / "svg-sprite.js"
        sprite_path.write_text(sprite_js, encoding="utf-8")

        worker_source = DISCOURSE / "app" / "views" / "static" / "service-worker.js.erb"
        worker_template = worker_source.read_text(encoding="utf-8")
        base_url_expr = "<%= Discourse.base_url %>"
        base_path_expr = "<%= Discourse.base_path %>"
        if worker_template.count(base_url_expr) != 2 or worker_template.count(base_path_expr) != 1:
            fail("pinned service-worker ERB expressions changed; review adaptation before staging")
        worker_template = worker_template.replace(base_url_expr, "__MINIMAL_BASE_URL__")
        worker_template = worker_template.replace(base_path_expr, "__MINIMAL_BASE_PATH__")
        worker_template, plugin_blocks = re.subn(
            r"<% DiscoursePluginRegistry\.service_workers\.each do \|js\| %>.*?<% end %>",
            "/* Native extraction omits Rails-registered plugin worker hooks. */",
            worker_template,
            flags=re.DOTALL,
        )
        if plugin_blocks != 1 or "<%" in worker_template:
            fail("could not safely adapt all service-worker ERB; no output staged")
        worker_output = temporary / "service-worker.js"
        worker_output.write_text(worker_template, encoding="utf-8")

        gem_lookup = 'spec = Gem::Specification.find_by_name("discourse-emojis"); puts "#{spec.full_gem_path}|#{spec.version}"'
        gem_result = subprocess.run(["bundle", "exec", "ruby", "-e", gem_lookup], cwd=DISCOURSE, check=True, text=True, capture_output=True)
        gem_root_text, emoji_version = gem_result.stdout.strip().rsplit("|", 1)
        if emoji_version != "1.0.47":
            fail(f"expected pinned discourse-emojis 1.0.47; found {emoji_version}")
        emoji_root = Path(gem_root_text) / "dist" / "emoji"
        emoji_source = emoji_root / "twemoji"
        if not emoji_source.is_dir():
            fail(f"pinned Twemoji source directory missing: {emoji_source}")
        emoji_files = []
        for source in sorted(path for path in emoji_source.rglob("*") if path.is_file()):
            relative = source.relative_to(emoji_source)
            target = temporary / "images" / "emoji" / "twitter" / relative
            copy_file(source, target)
            emoji_files.append({
                "url": f"/images/emoji/twitter/{relative.as_posix()}",
                "source": str(source.relative_to(ROOT)),
                "sha256": sha(source),
            })
        required_emoji = ("wave.png", "speaking_head.png")
        for name in required_emoji:
            if not (temporary / "images" / "emoji" / "twitter" / name).is_file():
                fail(f"pinned emoji image missing: {name}")

        core_manifest = json.loads(manifest_path.read_text(encoding="utf-8"))
        descriptor = {
            "format": 1,
            "source": {
                "discourse_commit": subprocess.check_output(["git", "-C", str(DISCOURSE), "rev-parse", "HEAD"], text=True).strip(),
                "discourse_version": re.search(r'STRING = "([^"]+)"', (DISCOURSE / "lib" / "version.rb").read_text(encoding="utf-8")).group(1),
                "layout": "app/views/layouts/application.html.erb",
                "layout_blob": "b938cb0c9c750a66785dbe8cd2d70e3db97845f1",
                "preloader": "lib/application_layout_preloader.rb",
                "preloader_blob": "1a79d1c06aae3d730bb157f4e49aaa1329df6249",
                "setup_and_importmap": "app/helpers/application_helper.rb",
                "importmap_source": "lib/ember_assets.rb",
                "locale_source": str(locale_source.relative_to(ROOT)),
                "locale_helper": "lib/js_locale_helper.rb",
                "load_moment_source": "frontend/discourse/app/lib/load-moment.js",
                "icons_source": str(svg_root.relative_to(ROOT)),
            },
            "core_ember": {
                "manifest_url_prefix": "/assets/discourse/",
                "entrypoints": core_manifest.get("entrypoints", {}),
                "dynamicEntrypoints": core_manifest.get("dynamicEntrypoints", {}),
                "importMap": core_manifest.get("importMap", {}),
                "chunks": core_manifest.get("chunks", {}),
                "note": "URLs are relative to /assets/discourse/; include root/prefix and .js using the original manifest values.",
            },
            "css": css_manifest,
            "theme_css": {
                "default_theme_id": palette["theme_id"],
                "theme": "Foundation",
                "available": True,
                "color_scheme_id": palette["color_scheme_id"],
                "color_scheme_name": palette["color_scheme_name"],
                "css_url": "/assets/native/css/color-definitions.css",
                "gap": "Foundation common/desktop/mobile theme CSS remains absent; common.scss is unified and the current color definitions/font variables are compiled from pinned source.",
                "source_candidates": [],
                "asset_processor_digest": palette["asset_processor_digest"],
                "asset_processor_path": str(Path(palette["asset_processor_path"]).relative_to(ROOT)),
                "asset_processor_sha256": palette["asset_processor_sha256"],
            },
            "fonts": {
                "source_root": str(Path(palette["font_root"]).relative_to(ROOT)),
                "files": fonts,
            },
            "palette_compiler_sources": palette_source_rows,
            "locale": {
                "url": "/assets/native/locale/en.js",
                "source": str(locale_source.relative_to(ROOT)),
                "source_sha256": sha(locale_source),
                "date_source": str(date_source.relative_to(ROOT)),
                "date_source_sha256": sha(date_source),
                "sha256": sha(locale_output),
                "limitations": ["English core client YAML only; no plugin/theme/override translations or compiled MessageFormat bundle. The messageFormatData function returns an empty bundle so the I18n loader initializes, but *_MF translations are omitted."],
            },
            "browser_scripts": browser_scripts,
            "service_worker": {
                "url": "/service-worker.js",
                "source": str(worker_source.relative_to(ROOT)),
                "source_sha256": sha(worker_source),
                "sha256": sha(worker_output),
                "path_placeholders": ["__MINIMAL_BASE_URL__", "__MINIMAL_BASE_PATH__"],
                "adaptation": "Pinned ERB expressions become placeholders expanded by the native handler using trusted origin/base_uri; Rails plugin service_workers block is deliberately omitted.",
            },
            "emoji": {
                "version": emoji_version,
                "source_package": f"discourse-emojis-{emoji_version}",
                "source_directory": str(emoji_source.relative_to(ROOT)),
                "requested_url_directory": "/images/emoji/twitter/",
                "source_url_directory": "/images/emoji/twemoji/",
                "file_count": len(emoji_files),
                "files": emoji_files,
                "limitations": ["Twitter is the legacy public URL alias for the pinned package's Twemoji directory; this extraction stages the Twemoji set only."],
            },
            "icons": {
                "sprite_url": "/assets/native/icons/svg-sprite.js",
                "source_directory": str(svg_root.relative_to(ROOT)),
                "svg_count": len(svg_files),
                "symbol_count": len(symbols),
                "sha256": sha(sprite_path),
                "files": icon_files,
                "limitations": ["Core vendor SVG symbols only; plugin/theme icon additions are not included."],
            },
            "images": images,
        }
        (temporary / "manifest.json").write_text(json.dumps(descriptor, indent=2, ensure_ascii=False) + "\n", encoding="utf-8")
        if OUTPUT.exists():
            shutil.rmtree(OUTPUT)
        os.replace(temporary, OUTPUT)
    except BaseException:
        shutil.rmtree(temporary, ignore_errors=True)
        raise

    print(f"Staged pinned Discourse assets at {OUTPUT.relative_to(ROOT)}")
    print(f"Descriptor: {(OUTPUT / 'manifest.json').relative_to(ROOT)}")
    print("Core Ember JS reused; Foundation palette compiled by a synchronous task-only read-only Rails runner (no HTTP server or source/output-tree writes).")


if __name__ == "__main__":
    main()

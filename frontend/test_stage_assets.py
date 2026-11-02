#!/usr/bin/env python3
"""Focused checks for generated pinned frontend assets; run after stage-assets.py."""
import json
from pathlib import Path
import re
import xml.etree.ElementTree as ET

ROOT = Path(__file__).resolve().parents[1]
STAGE = ROOT / "build" / "assets" / "native"
manifest = json.loads((STAGE / "manifest.json").read_text(encoding="utf-8"))

assert manifest['core_ember']['manifest_url_prefix'] == '/assets/discourse/'
core_manifest = ROOT / 'build/assets/discourse/manifest/manifest.json'
assert manifest['core_ember']['manifest_sha256'] == __import__('hashlib').sha256(core_manifest.read_bytes()).hexdigest()
locale_text = (STAGE / 'locale/en.js').read_text()
plugin_css = (STAGE / 'css/discourse-reactions.css').read_text()
assert '.mobile-view .discourse-reactions-counter{margin:0}' in plugin_css
assert '.desktop-view' in plugin_css
assert '"discourse_reactions"' in locale_text and '"aria_label"' in locale_text and '"users_popup"' in locale_text
assert manifest['locale']['plugin_source_sha256'] == __import__('hashlib').sha256((ROOT.parent / 'discourse/plugins/discourse-reactions/config/locales/client.en.yml').read_bytes()).hexdigest()

assert manifest["theme_css"]["default_theme_id"] == -1
assert manifest["theme_css"]["available"] is True
assert manifest["theme_css"]["color_scheme_id"] == -1
assert "common/desktop/mobile theme CSS remains absent" in manifest["theme_css"]["gap"]
processor = ROOT.parent / manifest["theme_css"]["asset_processor_path"]
assert processor.is_file()
import hashlib
assert hashlib.sha256(processor.read_bytes()).hexdigest() == manifest["theme_css"]["asset_processor_sha256"]

common = (STAGE / "css" / "common.css").read_text(encoding="utf-8")
assert 'url("/images/' not in common and "localhost:3000" not in common
assert 'url("../images/firenoise.png")' in common
palette = (STAGE / "css" / "color-definitions.css").read_text(encoding="utf-8")
assert "--primary:" in palette
assert "--secondary:" in palette
assert "localhost:3000" not in palette
font_refs = re.findall(r'url\(["\']fonts/([^?"\']+)', palette)
assert font_refs
for name in font_refs:
    assert (STAGE / "css" / "fonts" / name).is_file(), name

sprite_js = (STAGE / "icons" / "svg-sprite.js").read_text(encoding="utf-8")
prefix = "window.__svg_sprite = "
assert sprite_js.startswith(prefix)
sprite_text = json.loads(sprite_js[len(prefix):].strip().removesuffix(";"))
assert "ns0:" not in sprite_text and "xmlns:ns" not in sprite_text
svg = ET.fromstring(sprite_text)
ns = "{http://www.w3.org/2000/svg}"
symbols = {node.attrib["id"] for node in svg.findall(f".//{ns}symbol")}
assert {"bars", "far-calendar-check", "fab-github"}.issubset(symbols)

for name in ("wave.png", "speaking_head.png"):
    assert (STAGE / "images" / "emoji" / "twitter" / name).is_file()
assert manifest["emoji"]["source_package"] == "discourse-emojis-1.0.47"
assert "__MINIMAL_BASE_URL__" in (STAGE / "service-worker.js").read_text(encoding="utf-8")
print(f"frontend stage checks passed: {len(symbols)} resolvable symbols, {len(font_refs)} font faces")

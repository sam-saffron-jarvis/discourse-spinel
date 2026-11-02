#!/usr/bin/env python3
"""Verify extracted source provenance; no writes/network/database access."""
import hashlib
import json
import os
from pathlib import Path
import subprocess

manifest = json.loads(Path("SOURCE_MANIFEST.json").read_text())
reference = Path("../discourse")
run = Path(os.environ.get("DSPINEL_ROOT", "..")) / "run"
assert subprocess.check_output(["git", "-C", str(reference), "rev-parse", "HEAD"], text=True).strip() == manifest["original_revision"]
count = 0
for entry in manifest["entries"]:
    for source in entry.get("sources", []):
        if source["origin"] == "discourse":
            root = reference
        elif source["origin"] == "discourse-emojis":
            root = run / "bundle/ruby/4.0.0/gems/discourse-emojis-1.0.47"
        elif source["origin"] == "message_bus":
            root = run / "bundle/ruby/4.0.0/gems/message_bus-5.0.0"
        elif source["origin"] == "discourse-fonts":
            root = run / "bundle/ruby/4.0.0/gems/discourse-fonts-0.0.19"
        elif source["origin"] == "fast_blank":
            root = run / "bundle/ruby/4.0.0/gems/fast_blank-1.0.1"
        else:
            raise AssertionError(source["origin"])
        assert hashlib.sha256((root / source["path"]).read_bytes()).hexdigest() == source["sha256"], source["path"]
        count += 1
    for source in entry.get("files", []):
        assert hashlib.sha256(Path(source["path"]).read_bytes()).hexdigest() == source["sha256"], source["path"]
        count += 1
assert Path("frontend/reference/application.html.erb").read_bytes() == (reference / "app/views/layouts/application.html.erb").read_bytes()
reaction_copies = list(Path("reference/reactions-upstream").rglob("*"))
assert sum(p.is_file() for p in reaction_copies) == 10
for copy in reaction_copies:
    if copy.is_file():
        assert copy.read_bytes() == (reference / "plugins/discourse-reactions" / copy.relative_to("reference/reactions-upstream")).read_bytes(), str(copy)
colors = (reference / "lib/letter_avatar.rb").read_text()
assert colors[colors.index("  COLORS = ["):colors.rfind("\nend")] in Path("lib/letter_avatar_colors.rb").read_text()
for copy in Path('reference/reaction-metadata-sources').glob('*.rb'):
    assert copy.read_bytes() == (reference / 'plugins/discourse-reactions/lib/discourse_reactions' / copy.name).read_bytes(), str(copy)
browser_sources = json.loads(Path('reference/reactions-browser-sources/manifest.json').read_text())
assert browser_sources['revision'] == manifest['original_revision']
for key, row in browser_sources['files'].items():
    original = reference / row['path']
    assert hashlib.sha256(original.read_bytes()).hexdigest() == row['sha256'], row['path']
    candidates = [Path(row['copy'])] if row.get('copy') else []
    candidates.append(Path('reference/reactions-browser-sources') / original.name)
    candidates.extend(Path('frontend/reactions').rglob(original.name))
    candidates.extend(Path('reference/reactions-upstream').rglob(original.name))
    assert any(copy.is_file() and copy.read_bytes() == original.read_bytes() for copy in candidates), ('missing unchanged original copy', key, row['path'])
subprocess.run(['python3', 'tools/carry-emoji-existence.py', '--check'], check=True)
ledger = json.loads(Path("PLUGIN_SUPPORT.json").read_text())
assert {p.parent.name for p in reference.glob("plugins/*/plugin.rb")} == {p["plugin"] for p in ledger["plugins"]}
subprocess.run(["ruby", "reference/generate-client-settings.rb", "--check"], check=True)
print(f"Provenance passed: {count} source/vendor hashes, unchanged layout/palette, {len(ledger['plugins'])} plugin ledger entries")

profiler_root = Path("vendor/rack-mini-profiler")
profiler_manifest = json.loads((profiler_root / "MANIFEST.json").read_text())
assert profiler_manifest["version"] == "5.0.0"
lock = (reference / "Gemfile.lock").read_text()
assert "rack-mini-profiler (5.0.0) sha256=" + profiler_manifest["locked_gem_sha256"] in lock
for row in profiler_manifest["files"]:
    content = (profiler_root / row["path"]).read_bytes()
    assert hashlib.sha256(content).hexdigest() == row["sha256"], row["path"]
    if row["unchanged_upstream"]:
        assert content == (run / "bundle/ruby/4.0.0/gems/rack-mini-profiler-5.0.0" / row["source"]).read_bytes(), row["source"]
print("Profiler provenance passed: native core/license hashes and unchanged locked5.0.0 JS/CSS/vendor/bootstrap")

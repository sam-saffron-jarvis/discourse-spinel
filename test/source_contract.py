#!/usr/bin/env python3
"""Verify extracted source provenance; no writes/network/database access."""
import hashlib
import json
from pathlib import Path
import subprocess

manifest = json.loads(Path("SOURCE_MANIFEST.json").read_text())
reference = Path("../discourse")
assert subprocess.check_output(["git", "-C", str(reference), "rev-parse", "HEAD"], text=True).strip() == manifest["original_revision"]
count = 0
for entry in manifest["entries"]:
    for source in entry.get("sources", []):
        if source["origin"] == "discourse":
            root = reference
        elif source["origin"] == "discourse-emojis":
            root = Path("../run/bundle/ruby/4.0.0/gems/discourse-emojis-1.0.47")
        elif source["origin"] == "message_bus":
            root = Path("../run/bundle/ruby/4.0.0/gems/message_bus-5.0.0")
        elif source["origin"] == "discourse-fonts":
            root = Path("../run/bundle/ruby/4.0.0/gems/discourse-fonts-0.0.19")
        else:
            raise AssertionError(source["origin"])
        assert hashlib.sha256((root / source["path"]).read_bytes()).hexdigest() == source["sha256"], source["path"]
        count += 1
    for source in entry.get("files", []):
        assert hashlib.sha256(Path(source["path"]).read_bytes()).hexdigest() == source["sha256"], source["path"]
        count += 1
assert Path("frontend/reference/application.html.erb").read_bytes() == (reference / "app/views/layouts/application.html.erb").read_bytes()
colors = (reference / "lib/letter_avatar.rb").read_text()
assert colors[colors.index("  COLORS = ["):colors.rfind("\nend")] in Path("lib/letter_avatar_colors.rb").read_text()
ledger = json.loads(Path("PLUGIN_SUPPORT.json").read_text())
assert {p.parent.name for p in reference.glob("plugins/*/plugin.rb")} == {p["plugin"] for p in ledger["plugins"]}
subprocess.run(["ruby", "reference/generate-client-settings.rb", "--check"], check=True)
print(f"Provenance passed: {count} source/vendor hashes, unchanged layout/palette, {len(ledger['plugins'])} plugin ledger entries")

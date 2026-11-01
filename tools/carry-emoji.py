#!/usr/bin/env python3
"""Carry source emoji data, NOT oracle output. Adapt Emoji.lookup_unicode.
Input: installed discourse-emojis 1.0.47 gem, named in ../discourse/Gemfile.lock.
No network or Rails/DB call. Re-run only when deliberately updating provenance.
"""
import json
from pathlib import Path

source = Path("../run/bundle/ruby/4.0.0/gems/discourse-emojis-1.0.47/dist")
emojis = json.loads((source / "emojis.json").read_text())
tones = set(json.loads((source / "tonable_emojis.json").read_text()))
lookup = {}
for emoji in emojis:
    name = emoji["name"]
    if name == "tm":
        continue
    points = [int(p, 16) for p in emoji["code"].split("-")]
    lookup[name] = "".join(map(chr, points))
    if name in tones:
        if len(points) > 1 and points[1] == 0xfe0f:
            del points[1]
        for index, tone in enumerate(range(0x1f3fb, 0x1f400), 2):
            lookup[f"{name}:t{index}"] = "".join(map(chr, points[:1] + [tone] + points[1:]))
for name, aliases in json.loads((source / "aliases.json").read_text()).items():
    if name in lookup:
        for alias in aliases:
            lookup[alias] = lookup[name]
Path("data").mkdir(exist_ok=True)
Path("data/emoji-unicode.json").write_text(json.dumps(lookup, ensure_ascii=False, sort_keys=True) + "\n")

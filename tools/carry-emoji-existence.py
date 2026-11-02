#!/usr/bin/env python3
"""Generate source-only Emoji.exists? metadata, not Rails output or site data.

Unlike lookup_unicode, existence retains tm and includes tone1 and toned aliases.
Emoji.load_standard calls create_from_db_item, which requires a source group.
"""
import argparse
import json
import os
from pathlib import Path

root = Path(os.environ.get('DSPINEL_ROOT', '..'))
source = root / 'run/bundle/ruby/4.0.0/gems/discourse-emojis-1.0.47/dist'
names = {icon['name'] for group in json.loads((source / 'groups.json').read_text()) for icon in group['icons']}
tones = set(json.loads((source / 'tonable_emojis.json').read_text()))
standard = {row['name']: row['name'] in tones for row in json.loads((source / 'emojis.json').read_text()) if row['name'] in names}
aliases = {alias: original for original, values in json.loads((source / 'aliases.json').read_text()).items() for alias in values}
output = json.dumps({'standard': standard, 'aliases': aliases}, sort_keys=True, separators=(',', ':')) + '\n'
path = Path('data/emoji-existence.json')
parser = argparse.ArgumentParser(description=__doc__)
parser.add_argument('--check', action='store_true')
args = parser.parse_args()
if args.check:
    assert path.read_text() == output, 'stale source emoji existence catalog'
else:
    path.write_text(output)
print(f'Verified source emoji existence metadata: {len(standard)} names, {len(aliases)} aliases')

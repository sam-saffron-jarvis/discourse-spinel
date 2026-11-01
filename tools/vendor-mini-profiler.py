#!/usr/bin/env python3
"""Vendor ONLY the small native core and byte-unchanged locked5.0.0 client.

No compiler outputs, mutable links, Rack/Rails, source gem modifications or network.
Run from this worktree. Reusable lane repository is the only source input.
"""
import hashlib
import json
from pathlib import Path
import shutil
import subprocess

source = Path('../rack-mini-profiler')
if subprocess.check_output(['git', '-C', str(source), 'status', '--porcelain'], text=True).strip():
    raise SystemExit('refusing to vendor uncommitted profiler source; commit the reusable repo first')
target = Path('vendor/rack-mini-profiler')
target.mkdir(parents=True, exist_ok=True)
files = {'spinel/lib/spinel_mini_profiler.rb': 'spinel_mini_profiler.rb',
         'LICENSE.txt': 'LICENSE.txt'}
for name in ['includes.js', 'includes.css', 'vendor.js', 'profile_handler.js']:
    files['lib/html/' + name] = 'html/' + name
rows = []
for src, dest in files.items():
    original = source / src
    output = target / dest
    output.parent.mkdir(parents=True, exist_ok=True)
    shutil.copyfile(original, output)
    rows.append(dict(source=src, path=dest, sha256=hashlib.sha256(output.read_bytes()).hexdigest(),
                     unchanged_upstream=src.startswith('lib/html/')))
manifest = dict(version='5.0.0', locked_gem_sha256='99c5ba087fa91c8d9ba80a43f6b2213f1ebead6e863d49286170129d391302e1',
                source_repository='../rack-mini-profiler',
                source_commit=subprocess.check_output(['git', '-C', str(source), 'rev-parse', 'HEAD'], text=True).strip(),
                files=rows)
(target / 'MANIFEST.json').write_text(json.dumps(manifest, indent=2) + '\n')
print('Vendored reusable native mini-profiler and unchanged5.0.0 client:', len(rows), 'files')

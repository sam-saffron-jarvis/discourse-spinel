"""Acquire a read-only serving-root capability, never a parsed graph/result."""
import hashlib
import json
import os
import subprocess
from pathlib import Path

PIN = '96ce8d44401a8a568ecc71561c26dca8ec6bfeb8'
MANIFEST = 'frontend/discourse/dist/manifest/manifest.json'
SOURCE_MEMBERS = ('lib/ember_assets.rb', 'app/helpers/application_helper.rb',
                  'config/initializers/assets.rb', 'config/environments/development.rb')

def sha(data): return hashlib.sha256(data).hexdigest()

def acquire(root, output):
    original = root / 'discourse'
    serving = root / 'fidelity/build/recovery24-frontend/source'
    # The specifically reviewed existing source-built tree; no arbitrary root,
    # build invocation, root mutation, cached graph or observer result accepted.
    assert serving.is_dir() and not serving.is_symlink()
    records = subprocess.check_output(['git', '-C', original, 'ls-tree', '-rz', PIN]).split(b'\0')
    entries = []
    for record in records:
        if not record: continue
        header, name = record.split(b'\t', 1)
        mode, kind, oid = header.split()
        assert kind == b'blob', (kind, name)
        entries.append((mode, name, oid))
    entries.sort(key=lambda entry: entry[1])
    batch = subprocess.run(['git', '-C', original, 'cat-file', '--batch'], input=b'\n'.join(x[2] for x in entries)+b'\n', capture_output=True, check=True).stdout
    offset = 0
    canonical = bytearray()
    for mode, name, oid in entries:
        end = batch.index(b'\n', offset)
        header = batch[offset:end].split()
        assert header[0] == oid and header[1] == b'blob'
        size = int(header[2]); data = batch[end+1:end+1+size]; offset = end+2+size
        relative = os.fsdecode(name)
        for tree in (original, serving):
            path = tree / relative
            actual = os.fsencode(os.readlink(path)) if mode == b'120000' else path.read_bytes()
            assert actual == data, f'changed pinned source: {tree}/{relative}'
        canonical += name + b'\0' + sha(data).encode() + b'\n'
    prior = json.loads((root / 'fidelity/build/recovery24-frontend/source-audit.json').read_text())
    assert prior['pinned_source_revision'] == PIN and not prior['mismatches']
    assert prior['front_end_manifest_sha256'] == sha((serving / MANIFEST).read_bytes())
    files = {member: sha((serving / member).read_bytes()) for member in SOURCE_MEMBERS}
    # Include every file in concrete initializer roots. File discovery and graph
    # acquisition are still executed by application/Propshaft, not supplied here.
    asset_roots = ('public/javascripts', 'frontend/discourse/dist/assets',
                   'frontend/discourse/dist/@embroider/virtual', 'frontend/discourse/scripts')
    for relative in asset_roots:
        path = serving / relative
        if path.exists():
            for file in sorted(path.rglob('*')):
                if file.is_file():
                    assert file.resolve().is_relative_to(serving.resolve()), f'asset escaped root: {file}'
                    files[str(file.relative_to(serving))] = sha(file.read_bytes())
    files[MANIFEST] = sha((serving / MANIFEST).read_bytes())
    status = 'frontend/discourse/dist/manifest/build.json'
    absent = []
    if (serving / status).exists(): files[status] = sha((serving / status).read_bytes())
    else: absent.append(status)
    report = {'pin': PIN, 'root': str(serving), 'source_blobs_per_tree': len(entries),
              'canonical_path_nul_sha256_newline_sha256': sha(canonical),
              'build_provenance': 'existing recovery24 actual pinned rolldown build; no rebuild or live service',
              'files': files, 'absent': absent, 'manifest': MANIFEST,
              'graph_or_urls_supplied': False, 'page_accepted': False}
    output.write_text(json.dumps(report, indent=2) + '\n')
    return report

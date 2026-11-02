#!/usr/bin/env python3
"""Fresh source/native checks and original details Chromium reader proof (016)."""
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess

ROOT = Path(__file__).resolve().parents[1]
OUT = ROOT / 'build/details'
OUT.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529)
ENV = dict(os.environ, DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development',
           REDIS_URL='redis://127.0.0.1:6399/0', PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000',
           TMPDIR=str(ROOT / 'build/tmp'), PYTHONDONTWRITEBYTECODE='1')


def interrupted(number, _frame):
    raise SystemExit(128 + number)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def command(argv, label):
    with (OUT / (label + '.stdout')).open('w') as out, (OUT / (label + '.stderr')).open('w') as err:
        child = subprocess.Popen(argv, cwd=ROOT, env=ENV, stdout=out, stderr=err, start_new_session=True)
        try:
            code = child.wait(timeout=300)
        except BaseException:
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=45)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
            raise
    assert code == 0, (argv, code, (OUT / (label + '.stdout')).read_text()[-4000:], (OUT / (label + '.stderr')).read_text()[-8000:])
    print('Passed: ' + label, flush=True)


def sha(path):
    return hashlib.sha256(Path(path).read_bytes()).hexdigest()


command(['python3', 'test/source_contract.py'], 'source-contract')
command(['python3', 'test/details_source_test.py'], 'source-native-fixtures')
command(['ruby', 'frontend/test_native_document.rb'], 'document-mri')
# Fresh native document test independently covers enabled/disabled CSS selection.
for suffix in ('', '.cruby'):
    (ROOT / ('build/test/document' + suffix)).unlink(missing_ok=True)
command(['spin', 'test', 'test/document.rb', 'test/site.rb'], 'document-settings-native')
command(['python3', 'frontend/test_stage_assets.py'], 'asset-checks')
command(['python3', 'test/details_assets_test.py'], 'asset-reuse-regressions')
command(['python3', 'test/browser_cleanup.py', '--details'], 'browser-cleanup')
command(['python3', 'test/details_browser_smoke.py'], 'chromium')
source = json.loads((OUT / 'source-fixtures.json').read_text())
native = json.loads((OUT / 'native-fixtures.json').read_text())
browser = json.loads((OUT / 'browser-report.json').read_text())
cases = browser['cases']
assert len(cases) == 16 and all('error' not in row for row in cases), browser
assert sum(row['evidence_kind'] == 'live-native-read-only-db' for row in cases) == 8
assert sum(row['evidence_kind'] == 'positive-source-native-fixture-cooked-transport' for row in cases) == 8
assert all(row['route_away_other_back_no_stale_state'] for row in cases)
assert all(not row['positive_live_e2e_claim'] for row in cases)
with socket.socket() as probe:
    probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
    probe.bind(('127.0.0.1', PORT))
files = ['source-fixtures.json', 'native-fixtures.json', 'live-inventory.json', 'browser-report.json']
summary = {'scope': __doc__, 'base': 'c971dcdabaafea0152299cdca2a3345198f489a2',
           'commit': subprocess.check_output(['git', 'rev-parse', 'HEAD'], cwd=ROOT, text=True).strip(),
           'source_tree_clean': not subprocess.check_output(['git', 'status', '--porcelain'], cwd=ROOT, text=True).strip(),
           'source_manifest_sha256': sha(ROOT / 'SOURCE_MANIFEST.json'),
           'source_revision': json.loads((ROOT / 'SOURCE_MANIFEST.json').read_text())['original_revision'],
           'binary_sha256': sha(ROOT / 'build/bin/discourse'),
           'native_manifest_sha256': sha(ROOT / 'build/assets/native/manifest.json'),
           'details_stage_manifest_sha256': sha(ROOT / 'build/assets/details-core/manifest.json'),
           'source_case_count': len(source['cases']), 'native_case_count': len(native['cases']),
           'browser_cases': len(cases), 'positive_live_e2e_claim': False,
           'live_inventory': json.loads((OUT / 'live-inventory.json').read_text()),
           'evidence': {name: sha(OUT / name) for name in files},
           'owned_native_test_port_released': True,
           'unsupported': ['runtime cooking/Markdown', 'composer/rich editor', 'email/reduce_cooked hooks', 'full plugin/all-core-plugin support']}
(OUT / 'report.json').write_text(json.dumps(summary, indent=2) + '\n')
print('Details passed: actual source cooking, compiled read-only native topic fixtures; 8 live/8 labeled cooked-transport Chromium cases; no positive live E2E claim')

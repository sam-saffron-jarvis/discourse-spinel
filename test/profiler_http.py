#!/usr/bin/env python3
"""Own native3529; real PG requests; no debug SQL endpoint or Ruby request server."""
import json
import os
from pathlib import Path
import signal
import socket
import statistics
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen


def stop(signum, _frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, stop)
signal.signal(signal.SIGINT, stop)

PORT = 3529
PREFIX = '/node/jarvis/widgets/discourse-spinel-app'
ORIGIN = f'http://127.0.0.1:{PORT}'
BASE = ORIGIN + PREFIX
OUTPUT = Path('build/profiler-http')
OUTPUT.mkdir(parents=True, exist_ok=True)


def free():
    with socket.socket() as s:
        s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        s.bind(('127.0.0.1', PORT))


def fetch(path, data=None, expected=200, origin=BASE, headers=None, method=None):
    request = Request(origin + path, data=data, headers=headers or {}, method=method)
    try:
        response = urlopen(request, timeout=10)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == expected, (path, response.status, body[:100])
        assert response.headers['Cache-Control'] == 'no-store'
        assert int(response.headers['Content-Length']) == len(body)
        assert response.headers['X-Content-Type-Options'] == 'nosniff'
        return dict(response.headers), body


def result(profile_id, expected=200):
    return fetch('/mini-profiler-resources/results', ('id=' + profile_id).encode(), expected,
                 headers={'Content-Type': 'application/x-www-form-urlencoded',
                          'X-Requested-With': 'XMLHttpRequest'})


report = {'port': PORT, 'prefix': PREFIX, 'modes': {}, 'comparison': 'same binary, live DB, JSON page0 workload; 5 warmups then 30 measured requests per mode; elapsed includes local HTTP; no speedup claim'}
responses = {}
for enabled in (False, True):
    free()
    label = 'enabled' if enabled else 'disabled'
    env = dict(os.environ, PORT=str(PORT), MINIMAL_BASE_URI=PREFIX, MINIMAL_ORIGIN=ORIGIN,
               MINIMAL_PROFILER='1' if enabled else '0', DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development',
               REDIS_URL='redis://127.0.0.1:6399/0')
    with (OUTPUT / f'{label}.log').open('w') as log:
        child = subprocess.Popen(['build/bin/discourse'], env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                assert child.poll() is None, label
                try:
                    fetch('/srv/status')
                    break
                except OSError:
                    time.sleep(.1)
            else:
                raise AssertionError('native readiness timeout')
            assert Path(f'/proc/{child.pid}/exe').resolve() == Path('build/bin/discourse').resolve()
            assert not Path(f'/proc/{child.pid}/task/{child.pid}/children').read_text().strip(), 'no hidden request server/subprocess'
            mode = {'native_elf': Path('build/bin/discourse').read_bytes()[:4] == b'\x7fELF', 'children': [], 'parity_pages': []}
            for suffix in ('', '?page=1'):
                headers, body = fetch('/latest.json' + suffix)
                if not enabled:
                    responses[suffix] = body
                    assert 'X-MiniProfiler-Ids' not in headers
                else:
                    assert responses[suffix] == body, 'profiler must not change latest bytes'
                    pid = headers['X-MiniProfiler-Ids']
                    h, raw = result(pid)
                    assert 'X-MiniProfiler-Ids' not in h
                    profile = json.loads(raw)
                    assert profile['sql_count'] > 1
                    assert profile['duration_milliseconds'] >= profile['duration_milliseconds_in_sql'] > 0
                    assert profile['sql_count'] == len(profile['root']['sql_timings'])
                    assert profile['request_path'] == '/latest.json'
                    mode['parity_pages'].append({'page': suffix or '0', 'sql_count': profile['sql_count'],
                                                'request_ms': profile['duration_milliseconds'], 'sql_ms': profile['duration_milliseconds_in_sql']})
            headers, html = fetch('/latest')
            if enabled:
                assert b'id="mini-profiler"' in html
                assert (PREFIX + '/mini-profiler-resources/includes.js').encode() in html
                pid = headers['X-MiniProfiler-Ids']
                profile = json.loads(result(pid)[1])
                assert profile['sql_count'] > 1
                for name, mime in [('includes.js', 'javascript'), ('vendor.js', 'javascript'), ('includes.css', 'css')]:
                    headers, asset = fetch('/mini-profiler-resources/' + name)
                    assert 'X-MiniProfiler-Ids' not in headers
                    assert mime in headers['Content-Type']
                    assert asset == Path('vendor/rack-mini-profiler/html/' + name).read_bytes()
                _, stripped = fetch('/mini-profiler-resources/results?id=' + pid, origin=ORIGIN)
                assert json.loads(stripped)['id'] == pid, 'widget stripped-prefix forwarding'
                for path, status in [('/results?id=bad', 400), ('/results?id=' + 'a' * 32, 404),
                                     ('/results?id=' + pid + '&id=' + pid, 400), ('/../LICENSE.txt', 404),
                                     ('/%2e%2e/LICENSE.txt', 404), ('/includes.js/../vendor.js', 404),
                                     ('/includes.js?v=unknown', 404), ('/snapshots', 404), ('/flamegraph', 404)]:
                    h, _ = fetch('/mini-profiler-resources' + path, expected=status)
                    assert 'X-MiniProfiler-Ids' not in h
                fetch('/mini-profiler-resources/results?id=' + pid, expected=405, method='DELETE')
                # Reject a bad app query without retaining ANY query string/body/header/cookie.
                headers, _ = fetch('/latest.json?password=do-not-store-secret', expected=400,
                                   headers={'Cookie': 'secret-cookie', 'Authorization': 'Bearer secret-token'})
                bad_profile = result(headers['X-MiniProfiler-Ids'])[1]
                assert b'secret' not in bad_profile and json.loads(bad_profile)['sql_count'] == 0
                headers, _ = fetch('/srv/status')
                clean = json.loads(result(headers['X-MiniProfiler-Ids'])[1])
                assert clean['sql_count'] == 1 and clean['custom_fields']['Failed PG calls'] == '0', 'no stale prior queries'
                old = headers['X-MiniProfiler-Ids']
                for _ in range(33):
                    fetch('/srv/status')
                result(old, expected=404)
                mode.update(upstream_asset_bytes_verified=True, traversal_rejected=True, no_query_cookie_auth_capture=True,
                            request_state_cleanup=True, storage_eviction=True, profiler_endpoints_unprofiled=True)
            else:
                assert b'id="mini-profiler"' not in html and 'X-MiniProfiler-Ids' not in headers
                for path in ('includes.js', 'includes.css', 'vendor.js', 'results?id=' + 'a' * 32):
                    fetch('/mini-profiler-resources/' + path, expected=404)
                mode['no_profiler_surface'] = True
            for _ in range(5):
                fetch('/latest.json')
            samples = []
            for _ in range(30):
                start = time.monotonic()
                fetch('/latest.json')
                samples.append((time.monotonic() - start) * 1000)
            mode['http_ms'] = {'samples': samples, 'median': statistics.median(samples),
                               'min': min(samples), 'p95': sorted(samples)[28]}
            report['modes'][label] = mode
        finally:
            child.terminate()
            child.wait(timeout=10)
    free()
report['byte_equal_latest_pages'] = True
report['ports_released'] = True
(OUTPUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('Profiler HTTP passed: own native ELF; disabled surface absent; live latest pages byte-identical; prefixed real assets/results; privacy, traversal, state cleanup and size eviction')
print('Comparable warmed HTTP medians ms:', {key: round(mode['http_ms']['median'], 3) for key, mode in report['modes'].items()})

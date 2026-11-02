#!/usr/bin/env python3
"""Executable bounded plugin contract. Only own native children and read-only oracles."""
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import parse_qs, quote, urlsplit
from urllib.request import Request, urlopen

ROOT = Path.cwd()
OUTPUT = ROOT / 'build/plugin'
OUTPUT.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529)
PREFIX = '/node/jarvis/widgets/discourse-spinel-app'
ENV = dict(os.environ, DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development',
           REDIS_URL='redis://127.0.0.1:6399/0', PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000',
           TMPDIR=str(ROOT / 'build/tmp'), PYTHONDONTWRITEBYTECODE='1')


def interrupted(signum, _frame):
    raise SystemExit(128 + signum)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def oracle(script, name):
    with (OUTPUT / f'{name}.json').open('w') as out, (OUTPUT / f'{name}.stderr').open('w') as err:
        subprocess.run(['bin/rails', 'runner', str(ROOT / 'reference' / script)],
                       cwd=ROOT.parent / 'discourse', env=ENV, stdout=out, stderr=err, timeout=120, check=True)
    return json.loads((OUTPUT / f'{name}.json').read_text())


def fetch(path, accept=None, expected=200, method='GET', cookie=False, xhr=False):
    headers = {'Accept': accept} if accept else {}
    if xhr:
        headers['X-Requested-With'] = 'XMLHttpRequest'
    if cookie:
        headers.update({'Cookie': '_forum_session=private-cookie-do-not-record',
                        'Authorization': 'Bearer private-auth-do-not-record'})
    try:
        response = urlopen(Request(f'http://127.0.0.1:{PORT}' + path, headers=headers, method=method), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == expected, (path, response.status, expected, body)
        assert response.headers['Cache-Control'] == 'no-store'
        assert response.headers['X-Content-Type-Options'] == 'nosniff'
        return body, dict(response.headers)


def profile(headers, prefix):
    pid = headers['X-MiniProfiler-Ids']
    body, _ = fetch(prefix + '/mini-profiler-resources/results?id=' + pid)
    return json.loads(body)


subprocess.run(['python3', 'test/source_contract.py'], env=ENV, check=True)
# spin currently misses changed required files in cached-test dependency checks.
# Always recompile/run this OWN fixture binary and require its fresh side effect.
(ROOT / 'build/test/reactions').unlink(missing_ok=True)
(ROOT / 'build/test/reactions.cruby').unlink(missing_ok=True)
(ROOT / 'build/reactions-fixtures-native.json').unlink(missing_ok=True)
subprocess.run(['spin', 'test', 'test/reactions.rb'], env=ENV, check=True)
source_fixtures = oracle('check-reactions-fixtures.rb', 'source-fixtures')
assert source_fixtures['case_count'] >= 6
assert any(row['total'] > 0 and row['rows'] for row in source_fixtures['cases']), 'positive source query fixtures required'
live = oracle('capture-reactions-rails.rb', 'rails-live')
assert live['read_only'] and live['settings']['discourse_reactions_enabled'] is True
assert len(live['post_selection']['visible_posts']) >= 3
plain_cases = [row for row in live['requests'] if row['case'] == 'extensionless_plain_accept']
assert plain_cases and all('users' not in row for row in plain_cases), 'source plain HTML must not execute plugin JSON action'
cases = [row for row in live['requests'] if row['case'] != 'extensionless_plain_accept']
if live.get('denied_post_request'):
    cases.append(live['denied_post_request'])
assert all('users' in row and 'total_rows' in row for row in cases if row['status'] == 200)
assert any(row['status'] == 200 for row in cases)
# Disabled plugin callback is a separately labeled source dependency fixture,
# never a claim about the live enabled site's settings or live reaction rows.
assert live['synthetic_disabled_plugin_request']['request']['status'] == 404
assert live['synthetic_disabled_plugin_request']['callback_confirmed']
responses = {}
report = {'scope': 'anonymous users-list only; not full plugin coverage',
          'global_live_counts': live['post_selection']['global_live_counts'],
          'live_sample_counts': live['post_selection']['sample_live_counts'],
          'live_visible_posts': [p['post_id'] for p in live['post_selection']['visible_posts']],
          'source_fixture_count': source_fixtures['case_count'],
          'plain_html_boundary': {'native_status': 501, 'source_statuses': [row['status'] for row in plain_cases],
                                  'reason': 'source check_xhr raises RenderEmpty; Rails application shell not extracted; no plugin users returned'},
          'modes': []}
for enabled in (False, True):
    for prefix in ('', PREFIX):
        with socket.socket() as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(('127.0.0.1', PORT))  # refuse occupied port; never kill its owner
        label = ('enabled' if enabled else 'disabled') + ('-prefix' if prefix else '-root')
        env = dict(ENV, PORT=str(PORT), MINIMAL_PROFILER='1' if enabled else '0',
                   MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=f'http://127.0.0.1:{PORT}')
        with (OUTPUT / f'{label}.log').open('w') as log:
            child = subprocess.Popen(['build/bin/discourse'], env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    assert child.poll() is None, label
                    try:
                        fetch(prefix + '/srv/status')
                        break
                    except OSError:
                        time.sleep(.1)
                else:
                    raise AssertionError('native readiness timeout')
                assert Path(f'/proc/{child.pid}/exe').resolve() == (ROOT / 'build/bin/discourse').resolve()
                sql_profiles = []
                for case in cases:
                    body, headers = fetch(prefix + case['path'], case['accept'], case['status'], cookie=True, xhr=case['xhr'])
                    assert headers['Content-Type'] == 'application/json; charset=utf-8'
                    if case['status'] == 200:
                        assert json.loads(body) == {'users': case['users'], 'total_rows': case['total_rows']}, (case, body)
                    key = (prefix, case['path'], case['accept'], case['xhr'])
                    if enabled:
                        assert body == responses[key], 'profile-disabled response parity'
                        result = profile(headers, prefix)
                        assert result['name'].startswith('/discourse-reactions/posts/')
                        assert result['name'].endswith('/reactions-users-list.json')
                        assert '?' not in result['name'] and 'oracle-' not in json.dumps(result)
                        assert 'private-cookie' not in json.dumps(result) and 'private-auth' not in json.dumps(result)
                        timings = result['root']['sql_timings']
                        assert timings and result['sql_count'] >= len(timings)
                        sql = '\n'.join(row['formatted_command_string'] for row in timings)
                        assert 'private_message' not in sql, 'SQL literals must be redacted'
                        if case['status'] == 200:
                            assert 'discourse_reactions_reaction_users' in sql
                            reaction_filter = parse_qs(urlsplit(case['path']).query, keep_blank_values=True).get('reaction_value', [''])[0]
                            if not reaction_filter.strip(' \t\r\n\f\v\0') or reaction_filter == live['settings']['main_reaction']:
                                assert 'post_actions' in sql
                            else:
                                assert 'post_actions' not in sql, 'specific filter must execute only source reaction query branch'
                            assert '$1' in sql and '$3' in sql
                        else:
                            assert 'discourse_reactions_reaction_users' not in sql and 'post_actions' not in sql, 'missing/inaccessible posts must not query reactors'
                        assert all(timing['duration_milliseconds'] >= 0 for timing in timings)
                        sql_profiles.append({'path': case['path'], 'name': result['name'], 'sql_count': result['sql_count'],
                                             'sql_timings': timings, 'duration_milliseconds_in_sql': result['duration_milliseconds_in_sql']})
                    else:
                        assert 'X-MiniProfiler-Ids' not in headers
                        responses[key] = body
                for case in plain_cases:
                    body, _ = fetch(prefix + case['path'], expected=501)
                    assert 'users' not in json.loads(body), 'unsupported HTML shell must never claim plugin success'
                first = live['post_selection']['visible_posts'][0]['post_id']
                path = f'/discourse-reactions/posts/{first}/reactions-users-list.json'
                # Same real endpoint with prefix stripped as by the widget proxy.
                assert fetch(prefix + path)[0] == fetch(path)[0]
                for query in ['page[]=1', 'page[x]=1', 'limit[]=1', 'reaction_value[]=hugs', 'raw=true',
                              'page=1&page=2', 'post_id=1', 'id=1', 'page=2147483648',
                              'limit=999999999999999999999999', 'reaction_value=%ZZ',
                              'reaction_value=%00', 'reaction_value=%FF', 'reaction_value=' + 'a' * 257]:
                    fetch(prefix + path + '?' + query, expected=400)
                fetch(prefix + path, expected=405, method='PUT')
                fetch(prefix + path.replace(str(first) + '/', '-1/'), expected=400)
                # Bound, source-grounded filter injection must not become SQL or a
                # broader result. The value is accepted only as a prepared bind.
                injection = "' OR 1=1; -- private-sql-injection"
                injected_body, injected_headers = fetch(prefix + path + '?reaction_value=' + quote(injection))
                assert json.loads(injected_body) == {'users': [], 'total_rows': 0}
                if enabled:
                    assert injection not in json.dumps(profile(injected_headers, prefix))
                secret_filter = 'private-filter-never-in-profile'
                body, headers = fetch(prefix + path + '?reaction_value=' + secret_filter)
                assert json.loads(body) == {'users': [], 'total_rows': 0}
                if enabled:
                    result = profile(headers, prefix)
                    assert secret_filter not in json.dumps(result)
                    _, headers = fetch(prefix + '/srv/status')
                    clean = profile(headers, prefix)
                    assert clean['sql_count'] == 1
                    assert 'discourse_reactions_' not in json.dumps(clean), 'request state leak'
                assert not Path(f'/proc/{child.pid}/task/{child.pid}/children').read_text().strip(), 'native runtime must not launch helpers'
                report['modes'].append({'mode': label, 'live_http_cases': len(cases),
                                        'profile_parity': True, 'security_boundaries': True,
                                        'profiles': sql_profiles})
            finally:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
        with socket.socket() as s:
            s.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            s.bind(('127.0.0.1', PORT))
report['native_sha256'] = hashlib.sha256((ROOT / 'build/bin/discourse').read_bytes()).hexdigest()
(OUTPUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print(f"Plugin contract passed: {source_fixtures['case_count']} positive/negative source CTE cases; {len(cases)} fresh actual Rails/plugin live requests × root/prefix × profiler0/1; native security, SQL redaction and response parity")
print('Live sample counts (not fixture rows):', report['live_sample_counts'])

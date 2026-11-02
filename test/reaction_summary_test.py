#!/usr/bin/env python3
"""Fresh native HTTP contract for anonymous per-post reaction summaries."""
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import quote
from urllib.request import Request, urlopen

ROOT = Path.cwd()
OUT = ROOT / 'build/reaction-summary'
OUT.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529)
PREFIX = '/node/jarvis/widgets/discourse-spinel-app'
ENV = dict(os.environ, DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development',
           REDIS_URL='redis://127.0.0.1:6399/0',
           PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000',
           TMPDIR=str(ROOT / 'build/tmp'), PYTHONDONTWRITEBYTECODE='1')


def interrupted(signum, _frame):
    raise SystemExit(128 + signum)

signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def oracle(script, name):
    with (OUT / f'{name}.json').open('w') as out, (OUT / f'{name}.stderr').open('w') as err:
        subprocess.run(['bin/rails', 'runner', str(ROOT / 'reference' / script)],
                       cwd=ROOT.parent / 'discourse', env=ENV, stdout=out, stderr=err,
                       timeout=120, check=True)
    return json.loads((OUT / f'{name}.json').read_text())


def fetch(path, expected=200, method='GET', accept=None, xhr=False, auth=None):
    headers = {}
    if accept:
        headers['Accept'] = accept
    if xhr:
        headers['X-Requested-With'] = 'XMLHttpRequest'
    if auth == 'authorization':
        headers['Authorization'] = 'Bearer private-summary-auth'
    elif auth == 'api':
        headers['Api-Key'] = 'private-summary-api-key'
    elif auth == 'cookie':
        headers['Cookie'] = '_forum_session=private-summary-cookie'
    elif auth == 't_cookie':
        headers['Cookie'] = '_t=private-summary-t-cookie'
    elif auth == 'api_username':
        headers['Api-Username'] = 'private-summary-api-username'
    elif auth == 'api_user_id':
        headers['Api-User-Id'] = 'private-summary-api-user-id'
    elif auth == 'api_user_external_id':
        headers['Api-User-External-Id'] = 'private-summary-api-user-external-id'
    elif auth == 'user_api_key':
        headers['User-Api-Key'] = 'private-summary-user-api-key'
    elif auth == 'user_api_client_id':
        headers['User-Api-Client-Id'] = 'private-summary-api-client-id'
    elif auth == 'shared_session':
        headers['X-Shared-Session-Key'] = 'private-summary-shared-session'
    elif auth == 'discourse_logged_in':
        headers['Discourse-Logged-In'] = 'true'
    try:
        response = urlopen(Request(f'http://127.0.0.1:{PORT}' + path, headers=headers, method=method), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == expected, (path, method, auth, response.status, expected, body)
        assert response.headers['Cache-Control'] == 'no-store'
        assert response.headers['X-Content-Type-Options'] == 'nosniff'
        return body, dict(response.headers)


def profile(headers, prefix):
    pid = headers['X-MiniProfiler-Ids']
    return json.loads(fetch(prefix + '/mini-profiler-resources/results?id=' + pid)[0])


def assert_no_reactor_sql(result):
    encoded = json.dumps(result)
    for secret in ('private-summary-auth', 'private-summary-api-key', 'private-summary-cookie',
                   'private-summary-t-cookie', 'private-summary-api-username',
                   'private-summary-api-user-id', 'private-summary-api-user-external-id',
                   'private-summary-user-api-key', 'private-summary-api-client-id',
                   'private-summary-shared-session', 'oracle-secret', 'private-summary-injection'):
        assert secret not in encoded
    sql = '\n'.join(row['formatted_command_string'] for row in result.get('root', {}).get('sql_timings', []))
    assert 'discourse_reactions_reactions' not in sql
    assert 'discourse_reactions_reaction_users' not in sql
    assert 'post_actions' not in sql


# Native semantic fixtures are compiled freshly; source fixture verifier runs only
# against task PostgreSQL with read-only transaction/CTEs and actual plugin logic.
subprocess.run(['python3', 'test/source_contract.py'], env=ENV, check=True)
(ROOT / 'build/test/reaction_summary').unlink(missing_ok=True)
(ROOT / 'build/test/reaction_summary.cruby').unlink(missing_ok=True)
(ROOT / 'build/reaction-summary-fixtures-native.json').unlink(missing_ok=True)
subprocess.run(['spin', 'test', 'test/reaction_summary.rb'], env=ENV, check=True)
native_path = ROOT / 'build/reaction-summary-fixtures-native.json'
assert native_path.is_file(), 'native summary fixture generator did not write its required report'
(OUT / 'reaction-summary-fixtures-native.json').write_bytes(native_path.read_bytes())
native_fixtures = json.loads((OUT / 'reaction-summary-fixtures-native.json').read_text())
assert native_fixtures.get('synthetic') and native_fixtures.get('read_only')
assert native_fixtures.get('cases'), 'native summary fixtures must contain cases'
source = oracle('check-reaction-summary-fixtures.rb', 'source-fixtures')
assert source.get('read_only') and source.get('case_count', 0) == len(native_fixtures['cases']) >= 18
assert any(case.get('reaction_users') for case in source['cases']), 'positive source summary fixture is required'
live = oracle('capture-reaction-summary-rails.rb', 'rails-live')
assert live['read_only'] and live['settings']['reactions_enabled']
assert live['visibility']['sample_post_ids']
assert live['synthetic_disabled_plugin_request']['request']['status'] == 404
assert live['synthetic_disabled_plugin_request']['site_setting_mutated'] is False
normal_cases = [c for c in live['requests'] if c['case'] in
                ('json_no_filter', 'empty_filter', 'whitespace_filter', 'main_filter', 'unknown_filter',
                 'extensionless_json_accept', 'extensionless_xhr')]
assert normal_cases and all(c['status'] == 200 for c in normal_cases), 'all source-success summary cases are required'
assert all('reaction_users' in c for c in normal_cases)
assert all(isinstance(c['reaction_users'], list) for c in normal_cases)
plain_cases = [c for c in live['requests'] if c['case'] == 'extensionless_plain_html']
assert plain_cases and all('reaction_users' not in c for c in plain_cases), 'plain source HTML must not be mislabeled as summary JSON parity'
access_cases = [c for c in live['requests'] if c['case'] == 'missing_post' or
                c['case'].startswith('denied_') or c['case'] == 'deleted_post']
assert any(c['case'] == 'missing_post' for c in access_cases)
assert all(c['status'] in (403, 404) for c in access_cases), 'source access probes must actually execute the declared forbidden/not-found boundary'
assert source['source_fetch_post_guardian_visibility'] == native_fixtures['visibility']['cases']

summary = {'scope': 'anonymous per-post reaction summary only; not full plugin support',
           'live_counts': live['live_counts'],
           'live_empty_data_parity': not any(live['live_counts'].values()),
           'source_fixture_count': source['case_count'],
           'source_positive_fixture': True,
           'source_boundary_cases': {c['case']: c['status'] for c in live['requests'] if c['case'] not in
                                     ('json_no_filter', 'empty_filter', 'whitespace_filter', 'main_filter', 'unknown_filter',
                                      'extensionless_json_accept', 'extensionless_xhr')},
           'visibility_cases': [{'case': c['case'], 'status': c['status']} for c in access_cases],
           'plain_html_boundary': {'source_statuses': [c['status'] for c in live['requests'] if c['case'] == 'extensionless_plain_html'],
                                   'native_status': 501,
                                   'reason': 'unextracted Rails HTML application shell; no summary payload is claimed'},
           'modes': []}
response_baseline = {}
for enabled in (False, True):
    for prefix in ('', PREFIX):
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('127.0.0.1', PORT))
        label = ('enabled' if enabled else 'disabled') + ('-prefix' if prefix else '-root')
        env = dict(ENV, PORT=str(PORT), MINIMAL_PROFILER='1' if enabled else '0',
                   MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=f'http://127.0.0.1:{PORT}')
        with (OUT / f'{label}.log').open('w') as log:
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
                profiles = []
                for case in normal_cases:
                    path = case['path']
                    accept = 'application/json' if case['case'] == 'extensionless_json_accept' else None
                    xhr = case['case'] == 'extensionless_xhr'
                    body, headers = fetch(prefix + path, case['status'], accept=accept, xhr=xhr)
                    assert headers['Content-Type'] == 'application/json; charset=utf-8'
                    expected = {'reaction_users': case['reaction_users']}
                    assert json.loads(body) == expected, (case, body)
                    key = (prefix, path, accept, xhr)
                    if prefix:
                        assert body == response_baseline[('', path, accept, xhr)], 'root/prefix summary bytes differ'
                    if enabled:
                        assert body == response_baseline[key], 'profiler must not alter summary response bytes'
                        result = profile(headers, prefix)
                        assert result['name'].startswith('/discourse-reactions/posts/')
                        assert result['name'].endswith('/reactions-users.json')
                        encoded = json.dumps(result)
                        for secret in ('private-summary-auth', 'private-summary-api-key', 'private-summary-cookie', 'oracle-unknown-reaction'):
                            assert secret not in encoded
                        timings = result['root']['sql_timings']
                        assert timings and result['sql_count'] >= len(timings)
                        assert all(row['duration_milliseconds'] >= 0 for row in timings)
                        sql = '\n'.join(row['formatted_command_string'] for row in timings)
                        assert 'private_summary' not in sql
                        assert 'private_message' not in sql
                        if case['case'] in ('json_no_filter', 'main_filter'):
                            assert 'discourse_reactions_reactions' in sql
                            assert 'discourse_reactions_reaction_users' in sql
                            assert 'post_actions' in sql
                        elif case['case'] in ('empty_filter', 'whitespace_filter', 'unknown_filter'):
                            assert 'discourse_reactions_reactions' in sql
                            assert 'post_actions' not in sql, 'specific filters must not execute the source likes branch'
                        profiles.append({'case': case['case'], 'name': result['name'], 'sql_count': result['sql_count'],
                                         'sql_timings': timings, 'duration_milliseconds_in_sql': result['duration_milliseconds_in_sql']})
                    else:
                        assert 'X-MiniProfiler-Ids' not in headers
                        response_baseline[key] = body
                for case in access_cases:
                    body, headers = fetch(prefix + case['path'], case['status'])
                    key = (prefix, case['path'], 'access')
                    if prefix:
                        assert body == response_baseline[('', case['path'], 'access')], 'root/prefix access error bytes differ'
                    if enabled:
                        assert body == response_baseline[key], 'profiler altered access error bytes'
                        result = profile(headers, prefix)
                        assert_no_reactor_sql(result)
                        access_sql = result.get('root', {}).get('sql_timings', [])
                        profiles.append({'case': case['case'], 'name': result['name'], 'sql_count': result['sql_count'],
                                         'sql_timings': access_sql})
                    else:
                        response_baseline[key] = body
                pid = live['visibility']['sample_post_ids'][0]
                path = f'/discourse-reactions/posts/{pid}/reactions-users.json'
                assert fetch(prefix + path)[0] == fetch(path)[0], 'proxy prefix stripping must preserve response'
                for query in ('reaction_value[]=heart', 'reaction_value[x]=heart',
                              'reaction_value=a&reaction_value=b', 'unknown=1', 'id=1', 'post_id=1',
                              'api_key=private-summary-api-key', 'user_api_key=private-summary-user-api-key',
                              'page=1', 'limit=1', 'reaction_value=' + 'a' * 257,
                              'reaction_value=%ZZ', 'reaction_value=%00', 'reaction_value=%FF',
                              'x=' + 'x' * 2050):
                    fetch(prefix + path + '?' + query, expected=400)
                for auth in ('authorization', 'api', 'cookie', 't_cookie', 'api_username', 'api_user_id',
                             'api_user_external_id', 'user_api_key', 'user_api_client_id',
                             'shared_session', 'discourse_logged_in'):
                    _, auth_headers = fetch(prefix + path, expected=403, auth=auth)
                    if enabled:
                        assert_no_reactor_sql(profile(auth_headers, prefix))
                for method in ('PUT', 'POST', 'PATCH', 'DELETE', 'OPTIONS', 'HEAD'):
                    fetch(prefix + path, expected=405, method=method)
                fetch(prefix + path.replace(str(pid) + '/', '-1/'), expected=400)
                fetch(prefix + '/discourse-reactions/posts/01/reactions-users.json', expected=400)
                fetch(prefix + '/discourse-reactions/posts/2147483648/reactions-users.json', expected=400)
                fetch(prefix + '/discourse-reactions/posts/0/reactions-users.json', expected=404)
                injection = quote("' OR 1=1; -- private-summary-injection")
                injected, ih = fetch(prefix + path + '?reaction_value=' + injection)
                assert json.loads(injected) == {'reaction_users': []}
                if enabled:
                    injection_profile = profile(ih, prefix)
                    assert 'private-summary-injection' not in json.dumps(injection_profile)
                plain, _ = fetch(prefix + f'/discourse-reactions/posts/{pid}/reactions-users', expected=501)
                assert 'reaction_users' not in json.loads(plain)
                if enabled:
                    _, status_headers = fetch(prefix + '/srv/status')
                    assert_no_reactor_sql(profile(status_headers, prefix))
                assert not Path(f'/proc/{child.pid}/task/{child.pid}/children').read_text().strip(), 'native runtime launched a child'
                summary['modes'].append({'mode': label, 'summary_cases': len(normal_cases), 'profile_parity': True,
                                         'security_boundaries': True, 'profiles': profiles})
            finally:
                child.terminate()
                try:
                    child.wait(timeout=10)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait(timeout=10)
        with socket.socket() as sock:
            sock.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            sock.bind(('127.0.0.1', PORT))
summary['native_sha256'] = hashlib.sha256((ROOT / 'build/bin/discourse').read_bytes()).hexdigest()
(OUT / 'report.json').write_text(json.dumps(summary, indent=2) + '\n')
print(f"Reaction summary contract passed: {source['case_count']} source semantic fixtures and {len(normal_cases)} fresh live summary cases × root/prefix × profiler0/1")
print('Live counts (separate from positive source fixtures):', live['live_counts'])

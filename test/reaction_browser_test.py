#!/usr/bin/env python3
"""Compile/source-check metadata and drive the actual shipped read-only browser UI."""
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.error import HTTPError
from urllib.request import Request, urlopen

ROOT = Path.cwd()
OUT = ROOT / 'build/reaction-browser'
OUT.mkdir(parents=True, exist_ok=True)
PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529)
PREFIX = '/node/jarvis/widgets/discourse-spinel-app'
ENV = dict(os.environ, DATABASE_URL='postgres://discourse@127.0.0.1:5499/discourse_development',
           REDIS_URL='redis://127.0.0.1:6399/0', PGOPTIONS='-c default_transaction_read_only=on -c statement_timeout=15000',
           TMPDIR=str(ROOT / 'build/tmp'), PYTHONDONTWRITEBYTECODE='1')


def interrupted(number, _frame):
    raise SystemExit(128 + number)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def command(argv, label, cwd=ROOT):
    with (OUT / (label + '.stdout')).open('w') as out, (OUT / (label + '.stderr')).open('w') as err:
        child = subprocess.Popen(argv, cwd=cwd, env=ENV, stdout=out, stderr=err, start_new_session=True)
        try:
            code = child.wait(timeout=180)
        except BaseException:
            # Forward shutdown to the owned process group. In particular, do not
            # SIGKILL the browser driver and orphan its native/browser children.
            if child.poll() is None:
                os.killpg(child.pid, signal.SIGTERM)
                try:
                    child.wait(timeout=45)
                except subprocess.TimeoutExpired:
                    os.killpg(child.pid, signal.SIGKILL)
                    child.wait()
            raise
    if code:
        raise AssertionError((argv, code, (OUT / (label + '.stdout')).read_text()[-3000:], (OUT / (label + '.stderr')).read_text()[-6000:]))
    print('Passed: ' + label, flush=True)


def fetch(path, expected=200, method='GET'):
    try:
        response = urlopen(Request(f'http://127.0.0.1:{PORT}' + path, method=method), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        body = response.read()
        assert response.status == expected, (path, response.status, body)
        return body, dict(response.headers)


command(['python3', 'test/source_contract.py'], 'source-contract')
command(['python3', 'tools/carry-emoji-existence.py', '--check'], 'emoji-catalog')
# Spin only follows entrypoint mtimes, so remove just our owned fixture binaries.
for name in ('reaction-browser-fixtures-native', 'reaction-browser-fixtures-source', 'reaction-metadata-fixtures-native', 'reaction-topic-native', 'emoji-existence-native'):
    (ROOT / f'build/{name}.json').unlink(missing_ok=True)
for name in ('emoji_existence', 'reaction_metadata', 'reaction_metadata_browser', 'reaction_topic'):
    for suffix in ('', '.cruby'):
        (ROOT / f'build/test/{name}{suffix}').unlink(missing_ok=True)
command(['spin', 'test', 'test/emoji_existence.rb', 'test/reaction_metadata.rb', 'test/reaction_metadata_browser.rb'], 'native-fixtures')
command(['spin', 'test', 'test/reaction_topic.rb'], 'native-topic-fixtures')
command(['bin/rails', 'runner', str(ROOT / 'reference/check-emoji-existence.rb')], 'source-emoji', ROOT.parent / 'discourse')
command(['bin/rails', 'runner', str(ROOT / 'test/reaction_metadata_source.rb')], 'source-fixtures', ROOT.parent / 'discourse')
command(['bin/rails', 'runner', str(ROOT / 'reference/capture-topic-rails.rb')], 'rails-live', ROOT.parent / 'discourse')
source = json.loads((OUT / 'rails-live.stdout').read_text())
assert source['read_only'] and source['topics']
assert source['reaction_live_counts'] == {'reactions': 0, 'reaction_users': 0, 'likes': 0}, 'empty live DB evidence only; never seed live for this test'
fixture = json.loads((ROOT / 'build/reaction-browser-fixtures-native.json').read_text())
fixture_source = json.loads((ROOT / 'build/reaction-browser-fixtures-source.json').read_text())
assert fixture['read_only'] and fixture['synthetic'] and fixture_source['read_only'] and fixture_source['synthetic']
assert fixture_source['endpoints'] and fixture_source['metadata']['reaction_users_count'] > 30
for path in ('build/reaction-browser-fixtures-native.json', 'build/reaction-browser-fixtures-source.json', 'build/reaction-metadata-fixtures-native.json', 'build/reaction-topic-native.json', 'build/emoji-existence-native.json'):
    (OUT / Path(path).name).write_bytes((ROOT / path).read_bytes())

baseline = {}
modes = []
for enabled in (False, True):
    for prefix in ('', PREFIX):
        with socket.socket() as probe:
            probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
            probe.bind(('127.0.0.1', PORT))
        label = f"{'profile1' if enabled else 'profile0'}-{'prefix' if prefix else 'root'}"
        env = dict(ENV, PORT=str(PORT), MINIMAL_PROFILER='1' if enabled else '0', MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=f'http://127.0.0.1:{PORT}')
        with (OUT / (label + '.log')).open('w') as log:
            child = subprocess.Popen(['build/bin/discourse'], env=env, stdout=log, stderr=log)
            try:
                for _ in range(100):
                    assert child.poll() is None, 'owned native child exited'
                    try:
                        fetch(prefix + '/srv/status')
                        break
                    except OSError:
                        time.sleep(.1)
                else:
                    raise AssertionError('native readiness timeout')
                assert Path(f'/proc/{child.pid}/exe').resolve() == (ROOT / 'build/bin/discourse').resolve()
                cases = []
                for row in source['topics']:
                    topic_id = row['request']['topic_id']
                    path = prefix + f'/t/{topic_id}.json'
                    body, headers = fetch(path)
                    actual = json.loads(body)
                    expected = {**row['topic'], 'details': row['details'], 'post_stream': row['post_stream']}
                    # This test does not normalize away mounted cooked content:
                    # the existing topic HTTP tests cover that explicit deployment
                    # adaptation; these live sample posts have root-local emoji.
                    if prefix:
                        root = json.loads(baseline[(False, '', topic_id)])
                        assert {k: v for k, v in actual.items() if k != 'post_stream'} == {k: v for k, v in root.items() if k != 'post_stream'}
                        for post, root_post in zip(actual['post_stream']['posts'], root['post_stream']['posts']):
                            assert {k: v for k, v in post.items() if k != 'cooked'} == {k: v for k, v in root_post.items() if k != 'cooked'}
                    else:
                        assert actual == expected, (topic_id, actual, expected)
                    if enabled:
                        assert body == baseline[(False, prefix, topic_id)], 'profiling changed topic bytes'
                    baseline[(enabled, prefix, topic_id)] = body
                    for post in actual['post_stream']['posts']:
                        assert post['reactions'] == [] and post['reaction_users_count'] == 0, 'current live evidence requires genuinely empty data, not a fixture'
                        assert post['current_user_reaction'] is None and post['current_user_used_main_reaction'] is False
                    evidence = {'url': f'http://127.0.0.1:{PORT}' + path, 'topic_id': topic_id, 'post_ids': [post['id'] for post in actual['post_stream']['posts']], 'live_empty_state': True, 'body_sha256': hashlib.sha256(body).hexdigest()}
                    if enabled:
                        profile_id = headers['X-MiniProfiler-Ids']
                        profile = json.loads(fetch(prefix + '/mini-profiler-resources/results?id=' + profile_id)[0])
                        sql = [query['formatted_command_string'] for query in profile['root']['sql_timings']]
                        assert any('discourse_reactions_reactions' in text for text in sql)
                        assert any('discourse_reactions_reaction_users' in text for text in sql)
                        assert any('post_actions' in text for text in sql)
                        assert not any('fixture_user' in text or 'heart' in text or 'clap' in text for text in sql), 'profile SQL literals leaked'
                        evidence['actual_redacted_sql'] = sql
                        evidence['profile_id'] = profile_id
                    else:
                        assert 'X-MiniProfiler-Ids' not in headers
                    first = actual['post_stream']['posts'][0]['id']
                    empty_endpoint = prefix + f'/discourse-reactions/posts/{first}/reactions-users-list.json?page=0&limit=30'
                    endpoint = json.loads(fetch(empty_endpoint)[0])
                    assert endpoint == {'users': [], 'total_rows': 0}
                    evidence['real_native_users_list'] = {'path': empty_endpoint, 'body': endpoint}
                    toggle = prefix + f'/discourse-reactions/posts/{first}/custom-reactions/heart/toggle.json'
                    fetch(toggle, 405, 'PUT')
                    evidence['writes_fail_closed_status'] = 405
                    cases.append(evidence)
                modes.append({'profiler': enabled, 'prefix': prefix, 'cases': cases})
            finally:
                child.terminate()
                try:
                    child.wait(timeout=5)
                except subprocess.TimeoutExpired:
                    child.kill()
                    child.wait()

command(['python3', 'test/browser_cleanup.py', '--reactions'], 'browser-cleanup')
command(['python3', 'test/reaction_browser_smoke.py'], 'chromium')
report = {'scope': 'actual shipped anonymous read-only reactions counter/users menu only; no full plugin support',
          'live_evidence': 'real compiled native ELF / real read-only DB / empty data, root+prefix profiler0/1',
          'positive_evidence': 'separate compiled typed CTE metadata and actual NativeReactions.call source parity, then mocked browser data transport with original UI',
          'live_counts': source['reaction_live_counts'],
          'positive_live_native_e2e_claim': False, 'modes': modes,
          'binary_sha256': hashlib.sha256((ROOT / 'build/bin/discourse').read_bytes()).hexdigest(),
          'compile': json.loads((ROOT / 'build/compile.json').read_text()),
          'fixture_sha256': hashlib.sha256((ROOT / 'build/reaction-browser-fixtures-native.json').read_bytes()).hexdigest(),
          'browser': json.loads((OUT / 'browser-report.json').read_text())}
(OUT / 'report.json').write_text(json.dumps(report, indent=2) + '\n')
print('reaction-browser-test: native/source metadata + endpoint fixture parity, live-empty native HTTP and actual original desktop/phone root/prefix UI passed')

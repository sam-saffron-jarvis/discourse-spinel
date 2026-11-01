#!/usr/bin/env python3
"""Read-only native topic HTTP contract against fresh source getters."""
import json
import os
import copy
import runpy
from pathlib import Path
import subprocess
from urllib.error import HTTPError
from urllib.request import Request, urlopen

PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529), 'owned integration test ports only'
BASE = f'http://127.0.0.1:{PORT}'

def request(path, status=200, headers=None):
    try:
        response = urlopen(Request(BASE + path, headers=headers or {}), timeout=10)
    except HTTPError as error:
        response = error
    with response:
        data = response.read().decode()
        assert response.status == status, (path, response.status, status, data)
        return data, response.headers['Content-Type']

def api(path, status=200, headers=None):
    data, kind = request(path, status, headers)
    assert kind == 'application/json; charset=utf-8'
    return json.loads(data)

oracle = json.loads(Path('build/topic-rails.json').read_text())
candidates = []
for row in oracle['topics']:
    expected = row['topic']
    tid = expected['id']
    path = f"/t/{expected['slug']}/{tid}"
    native = api(path + '.json')
    candidates.append(native)
    assert native == api(f'/t/{tid}.json')
    assert native == api(path, headers={'Accept':'application/json'})
    assert native == api(path + '.json?track_visit=true&forceLoad=true')
    stream = native['post_stream']
    assert stream['posts'] and stream['stream']
    assert stream['posts'][0]['post_number'] == 1
    assert [p['id'] for p in stream['posts']] == stream['stream'][:20]
    assert all(p['topic_id'] == tid and p['post_type'] in (1,2,3) and p['deleted_at'] is None for p in stream['posts'])
    assert all('raw' not in p for p in stream['posts'])
    doc, kind = request(path)
    assert kind == 'text/html; charset=utf-8' and '<section id="main">' in doc
    assert f'topic_{tid}' in doc and '<link rel="canonical"' in doc
    assert '<article' not in doc, 'posts must render in actual Ember, not bespoke HTML'
    for query in ['show_deleted=true','filter=summary','post_ids[]=1','post_number=2','raw=true','track_visit=1','track_visit=true&track_visit=false','username_filters[]=system']:
        api(path + '.json?' + query, 400)
    for invalid in [f'/t/{tid}/0.json',f'/t/x/{tid}/-1.json',f'/t/x/{tid}/2/3.json']:
        api(invalid, 400)
    assert native == api(path + '.json'), 'bad input must not poison PG transaction'
Path('build/topic-native.json').write_text(json.dumps({'topics': candidates}, indent=2) + '\n')
subprocess.run(['python3','reference/compare-topic.py','--expected','build/topic-rails.json','--candidate','build/topic-native.json'], check=True)
# The verifier itself must not turn a missing field, altered cooked body,
# reordered stream or unexpected serializer field into a passing projection.
compare = runpy.run_path('reference/compare-topic.py')['differences']
original = next(topic for topic in candidates if len(topic['post_stream']['stream']) > 1)
assert not compare(original, copy.deepcopy(original))
for mutation in ['missing', 'extra', 'cooked', 'order', 'timestamp']:
    altered = copy.deepcopy(original)
    if mutation == 'missing':
        del altered['details']['notification_level']
    elif mutation == 'extra':
        altered['unimplemented_plugin_field'] = True
    elif mutation == 'cooked':
        altered['post_stream']['posts'][0]['cooked'] += '<p>not source data</p>'
    elif mutation == 'order':
        assert len(altered['post_stream']['stream']) > 1
        altered['post_stream']['stream'].reverse()
    else:
        altered['created_at'] = altered['created_at'].replace('Z', '+00:00')
    assert compare(original, altered), f'comparator concealed {mutation}'
for tid in oracle['guardian_inaccessible_topic_ids']:
    api(f'/t/{tid}.json',404)
for path in ['/t/2147483647.json','/t/999999999.json']:
    api(path,404)
for path in ['/t/0.json','/t/-1.json','/t/a/2147483648.json','/t/a/1%20OR%201=1.json','/t/a%2fb/1.json']:
    api(path,400)

near_oracle = json.loads(Path('build/topic-near-rails.json').read_text())
near_candidates = []
for row in near_oracle['topics']:
    tid = row['topic']['id']
    number = row['request']['post_number']
    native = api(f'/t/{tid}/{number}.json')
    assert native == api(f"/t/{row['topic']['slug']}/{tid}/{number}.json")
    near_candidates.append(native)
Path('build/topic-near-native.json').write_text(json.dumps({'topics':near_candidates},indent=2)+'\n')
subprocess.run(['python3','reference/compare-topic.py','--expected','build/topic-near-rails.json','--candidate','build/topic-near-native.json'], check=True)
print(f'Topic HTTP passed: {len(candidates)} fresh source topics, numeric/slug/document/near-post/malformed/query/visibility boundaries')

#!/usr/bin/env python3
"""Owned integration-port actual unmodified Ember topic click + direct document evidence."""
import html
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.request import urlopen
from playwright.sync_api import sync_playwright

PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529), 'owned integration test ports only'
PROFILER = os.environ.get('MINIMAL_PROFILER', '0') == '1'
OUTPUT = Path('build/topic-browser-profiler' if PROFILER else 'build/topic-browser')
OUTPUT.mkdir(parents=True, exist_ok=True)
reports = []
emoji_map = json.loads(Path('data/emoji-unicode.json').read_text())
interrupted = 0


def record_failure(evidence, error):
    # AssertionError() has an empty string message; presence, not truthiness of
    # that message, must decide whether a browser assertion failed.
    evidence['error'] = {'type': type(error).__name__, 'message': str(error)}


def assert_success(evidence):
    assert 'error' not in evidence, evidence


def terminate(number, _frame):
    global interrupted
    interrupted = number

def checkpoint():
    if interrupted:
        raise SystemExit(128 + interrupted)

signal.signal(signal.SIGTERM, terminate)
signal.signal(signal.SIGINT, terminate)

def fetch(url):
    with urlopen(url, timeout=10) as response:
        return json.load(response)

def run(prefix):
    checkpoint()
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(('127.0.0.1', PORT))
    origin = f'http://127.0.0.1:{PORT}'
    base = origin + prefix
    label = 'prefix' if prefix else 'root'
    env = dict(os.environ, PORT=str(PORT), MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=origin,
               DATABASE_URL=os.environ['DSPINEL_PG_URL'] + '/discourse_development',
               REDIS_URL='redis://127.0.0.1:6399/0')
    with (OUTPUT / f'{label}-server.log').open('w') as log:
        child = subprocess.Popen(['build/bin/discourse'], env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                checkpoint()
                assert child.poll() is None, 'owned native child exited'
                try:
                    fetch(base + '/srv/status')
                    break
                except OSError:
                    time.sleep(.1)
            latest = fetch(base + '/latest.json')['topic_list']['topics']
            assert len(latest) >= 2
            # First actual title link (coordinator path) plus another live topic.
            topics = latest[:2]
            with sync_playwright() as playwright:
                browser = playwright.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                    args=['--no-sandbox', '--disable-dev-shm-usage'])
                try:
                    for viewport, width, height, mobile in [('desktop',1440,1000,False),('phone',390,844,True)]:
                        for topic in topics:
                            for mode in ['click', 'direct']:
                                checkpoint()
                                context = browser.new_context(viewport={'width':width,'height':height},
                                    is_mobile=mobile, has_touch=mobile, device_scale_factor=1)
                                evidence = dict(prefix=prefix, viewport=viewport, topic_id=topic['id'], mode=mode,
                                    pageerrors=[], console=[], failed=[], responses=[], requests=[])
                                reports.append(evidence)
                                page = context.new_page()
                                page.on('pageerror', lambda error: evidence['pageerrors'].append({'message':str(error),'stack':error.stack}))
                                page.on('console', lambda msg: evidence['console'].append({'type':msg.type,'text':msg.text}))
                                page.on('requestfailed', lambda req: evidence['failed'].append({'url':req.url,'failure':req.failure}))
                                page.on('response', lambda res: evidence['responses'].append({'url':res.url,'status':res.status,'type':res.request.resource_type}))
                                page.on('request', lambda req: evidence['requests'].append({'url':req.url,'method':req.method,'body':req.post_data}) if req.resource_type in ('xhr','fetch') else None)
                                def local_only(route):
                                    if route.request.url.startswith(origin + '/'):
                                        route.continue_()
                                    else:
                                        evidence['failed'].append({'url':route.request.url,'failure':'remote forbidden'})
                                        route.abort()
                                page.route('**/*', local_only)
                                path = f"/t/{topic['slug']}/{topic['id']}"
                                api = fetch(base + path + '.json')
                                evidence['native'] = api
                                try:
                                    if mode == 'click':
                                        page.goto(base + '/latest', wait_until='commit', timeout=10000)
                                        link = page.locator(f".topic-list-item[data-topic-id='{topic['id']}'] a.title")
                                        link.wait_for(state='visible', timeout=30000)
                                        if PROFILER:
                                            # Like the profiler's dedicated UI test, wait for
                                            # the real upstream bootstrap before exercising
                                            # its asynchronous XHR/fetch observation hooks.
                                            page.locator('.profiler-result').first.wait_for(state='attached', timeout=15000)
                                            page.wait_for_function('window.MiniProfiler && window.MiniProfiler.patchesApplied', timeout=15000)
                                        evidence['clicked_href'] = link.get_attribute('href')
                                        assert evidence['clicked_href'] == prefix + path
                                        link.click()
                                    else:
                                        page.goto(base + path, wait_until='commit', timeout=10000)
                                    first = api['post_stream']['posts'][0]
                                    cooked = page.locator(f".topic-post article[data-post-id='{first['id']}'] .cooked")
                                    cooked.wait_for(state='visible', timeout=30000)
                                    for _ in range(20):
                                        checkpoint()
                                        page.wait_for_timeout(100)
                                    evidence['url'] = page.url
                                    title = page.locator('#topic-title .fancy-title')
                                    evidence['raw_title'] = title.inner_text()
                                    evidence['title'] = title.evaluate('''(element, emojiMap) => {
                                      const clone = element.cloneNode(true);
                                      clone.querySelectorAll('img.emoji').forEach(img => img.replaceWith(document.createTextNode(emojiMap[img.alt] || `:${img.alt}:`)));
                                      return clone.textContent.trim();
                                    }''', emoji_map)
                                    evidence['first_post_id'] = cooked.locator('xpath=ancestor::article').get_attribute('data-post-id')
                                    evidence['cooked_html'] = cooked.inner_html()
                                    evidence['cooked_text'] = cooked.inner_text()
                                    # Use the browser's own HTML parser to compare markup trees: Ember
                                    # may decorate links, so compare live text and every source paragraph.
                                    expected = page.evaluate('''cooked => {
                                      const node = document.createElement('div'); node.innerHTML = cooked;
                                      return {text:node.textContent.trim(), paragraphs:Array.from(node.querySelectorAll('p'), p=>p.textContent.trim())};
                                    }''', first['cooked'])
                                    actual = cooked.evaluate("node => ({text:node.textContent.trim(), paragraphs:Array.from(node.querySelectorAll('p'),p=>p.textContent.trim())})")
                                    evidence['expected_content'] = expected
                                    evidence['actual_content'] = actual
                                    assert first['post_number'] == 1
                                    assert evidence['first_post_id'] == str(first['id'])
                                    assert evidence['cooked_text'].strip() and actual == expected, (actual, expected)
                                    assert evidence['title'] == html.unescape(api.get('unicode_title', api['title']))
                                    assert page.url.startswith(base + path), page.url
                                    evidence['profiler_enabled'] = PROFILER
                                    if PROFILER:
                                        profile_name = f"/t/{topic['id']}" + ('.json' if mode == 'click' else '')
                                        result = page.locator('.profiler-result').filter(has=page.locator(f'.profiler-name[title="{profile_name}"]')).last
                                        result.wait_for(state='attached', timeout=15000)
                                        result.locator('.profiler-button').click()
                                        popup = result.locator('.profiler-popup')
                                        popup.wait_for(state='visible', timeout=5000)
                                        count_text = result.locator('.profiler-sql-count').inner_text()
                                        sql_count = int(''.join(c for c in count_text if c.isdigit()))
                                        assert sql_count > 0
                                        query_link = popup.locator('.profiler-queries-show').first
                                        query_link.evaluate("el => el.scrollIntoView({block:'center',inline:'center'})")
                                        query_link.click(timeout=5000)
                                        result.locator('.profiler-queries').wait_for(state='visible', timeout=5000)
                                        sql_rows = result.locator('.profiler-queries tbody tr:has(.query pre.prettyprint code)').evaluate_all("rows => rows.map(row => ({query:row.querySelector('.query pre.prettyprint code').innerText, timing:row.querySelector('td.profiler-info').innerText}))")
                                        assert len(sql_rows) == sql_count and any('FROM posts' in row['query'] for row in sql_rows)
                                        assert all(any(c.isdigit() for c in row['timing']) for row in sql_rows)
                                        evidence['topic_profile'] = {'name':profile_name, 'sql_count':sql_count, 'drilldown_rows':len(sql_rows), 'actual_post_sql':True}
                                        stem = f"{label}-{viewport}-{topic['id']}-{mode}"
                                        page.screenshot(path=str(OUTPUT / f'{stem}-profiler.png'), full_page=True)
                                        page.mouse.click(width - 5, height - 5)
                                        page.wait_for_function("!document.querySelector('.profiler-queries-bg')", timeout=5000)
                                        result.locator('.profiler-button').click()
                                        page.wait_for_function("Array.from(document.querySelectorAll('.profiler-popup')).every(p => p.style.display === 'none')", timeout=5000)
                                    else:
                                        assert page.locator('script#mini-profiler').count() == 0
                                        assert page.locator('.profiler-result').count() == 0
                                except Exception as error:
                                    record_failure(evidence, error)
                                finally:
                                    stem = f"{label}-{viewport}-{topic['id']}-{mode}"
                                    page.screenshot(path=str(OUTPUT / f'{stem}.png'), full_page=True)
                                    (OUTPUT / f'{stem}.html').write_text(page.content())
                                    context.close()
                                assert_success(evidence)
                                assert not evidence['pageerrors'], evidence['pageerrors']
                                assert not evidence['failed'], evidence['failed']
                                assert not [r for r in evidence['responses'] if r['status'] >= 400], evidence['responses']
                                assert not [c for c in evidence['console'] if c['type'] == 'error'], evidence['console']
                                assert all(r['url'].startswith(base + '/') for r in evidence['responses']), 'resource escaped mount'
                                print(f"Topic browser passed: {label} {viewport} topic{topic['id']} {mode}, first post {evidence['first_post_id']}")
                finally:
                    browser.close()
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()

if __name__ == '__main__':
    try:
        run('/node/jarvis/widgets/discourse-spinel-app')
        run('')
    finally:
        (OUTPUT / 'report.json').write_text(json.dumps(reports, indent=2) + '\n')

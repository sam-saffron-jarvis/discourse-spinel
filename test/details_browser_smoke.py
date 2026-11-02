#!/usr/bin/env python3
"""Original details reader: live native data vs source/native-verified cooked transport.

Positive cases replace ONLY the first post's cooked JSON transport, never DOM,
components or JS. This is not positive live plugin E2E and never runs a cooker.
"""
import hashlib
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.error import HTTPError
from urllib.parse import urlsplit
from urllib.request import urlopen
from playwright.sync_api import sync_playwright

PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529)
PREFIX = '/node/jarvis/widgets/discourse-spinel-app'
OUT = Path('build/details')
OUT.mkdir(parents=True, exist_ok=True)
REPORTS = []
LIVE_BYTES = {}
STOP = 0


def interrupted(number, _frame):
    global STOP
    STOP = number


def checkpoint():
    if STOP:
        raise SystemExit(128 + STOP)


signal.signal(signal.SIGTERM, interrupted)
signal.signal(signal.SIGINT, interrupted)


def fetch(url):
    with urlopen(url, timeout=10) as response:
        return json.load(response)


def clean(evidence, base):
    assert not evidence['pageerrors'], evidence
    assert not evidence['failed'], evidence
    assert not [row for row in evidence['console'] if row['type'] == 'error'], evidence
    assert not [row for row in evidence['responses'] if row['status'] >= 400], evidence
    assert all(row['url'].startswith(base + '/') for row in evidence['responses']), evidence


def states(article):
    return article.locator('.cooked details').evaluate_all('nodes => nodes.map(n => ({id:n.id, open:n.open, summary:n.querySelector(":scope > summary").textContent.trim()}))')


def opened(details):
    return details.evaluate('node => node.open')


def pointer_toggle(summary, details, expected):
    summary.click()
    summary.page.wait_for_function('(arg) => document.getElementById(arg.id).open === arg.open',
                                   arg={'id': details.get_attribute('id'), 'open': expected})


def keyboard_toggle(summary, details, key, expected):
    summary.focus()
    summary.press(key)
    summary.page.wait_for_function('(arg) => document.getElementById(arg.id).open === arg.open',
                                   arg={'id': details.get_attribute('id'), 'open': expected})


def details_for(article, summary):
    return article.locator('.cooked details').filter(has=article.page.get_by_text(summary, exact=True)).last


def exercise(page, article, fixture, evidence):
    # Source-generated fixture labels are test inputs, not expected response HTML.
    closed = details_for(article, 'Closed summary')
    initial_open = details_for(article, 'Open summary')
    outer = details_for(article, 'Outer summary')
    inner = details_for(article, 'Inner summary')
    summary = closed.locator(':scope > summary')
    body = closed.locator(':scope > p').first
    original = states(article)
    source_case = next(row for row in json.loads((OUT / 'source-fixtures.json').read_text())['cases'] if row['name'] == 'reader_combined')
    assert [{'summary': row['summary'], 'open': row['open']} for row in original] == [
        {'summary': row['summary'].strip(), 'open': row['open']} for row in source_case['tree']]
    assert any("<script>alert('escaped summary')</script>" == row['summary'] for row in original)
    evidence['source_tree_and_escaped_summary_match'] = True
    evidence['initial_state'] = original
    assert not opened(closed) and opened(initial_open) and not opened(outer) and not opened(inner)
    assert not body.is_visible()
    assert initial_open.locator(':scope > p').first.is_visible()
    assert not inner.locator(':scope > summary').is_visible()
    # The actual core decorator supplies stable IDs/listeners, not a plugin shim.
    assert all(row['id'].startswith('post-cooked-html__details-') for row in original)
    style = closed.evaluate('''node => {
      const s = getComputedStyle(node), summary = node.querySelector('summary');
      return {position:s.position, paddingTop:s.paddingTop, paddingLeft:s.paddingLeft,
        cursor:getComputedStyle(summary).cursor, display:getComputedStyle(summary).display,
        marker:getComputedStyle(summary, '::before').content};
    }''')
    assert style == {'position': 'relative', 'paddingTop': '4px', 'paddingLeft': '12px',
                     'cursor': 'pointer', 'display': 'block', 'marker': '"►"'}, style
    evidence['original_css_closed'] = style
    pointer_toggle(summary, closed, True)
    assert body.is_visible()
    assert summary.evaluate("node => getComputedStyle(node, '::before').content") == '"▼"'
    pointer_toggle(summary, closed, False)
    assert not body.is_visible()
    keyboard_toggle(summary, closed, 'Enter', True)
    assert body.is_visible()
    keyboard_toggle(summary, closed, 'Space', False)
    assert not body.is_visible()
    evidence['summary_pointer_enter_space_toggle'] = True

    pointer_toggle(outer.locator(':scope > summary'), outer, True)
    assert inner.locator(':scope > summary').is_visible()
    assert not inner.locator(':scope > p').first.is_visible()
    pointer_toggle(inner.locator(':scope > summary'), inner, True)
    assert opened(outer) and inner.locator(':scope > p').first.is_visible()
    pointer_toggle(outer.locator(':scope > summary'), outer, False)
    assert opened(inner) and not inner.locator(':scope > p').first.is_visible()
    pointer_toggle(outer.locator(':scope > summary'), outer, True)
    assert opened(inner) and inner.locator(':scope > p').first.is_visible()
    keyboard_toggle(inner.locator(':scope > summary'), inner, 'Enter', False)
    assert opened(outer) and not opened(inner) and opened(initial_open)
    evidence['nested_independence'] = True
    elided = details_for(article, 'Sanitizer summary')
    elided_summary = elided.locator(':scope > summary')
    elided_style = elided_summary.evaluate("node => ({marker:getComputedStyle(node, '::before').display, select:getComputedStyle(node).userSelect, display:getComputedStyle(node).display})")
    assert elided_style == {'marker': 'none', 'select': 'none', 'display': 'flex'}, elided_style
    pointer_toggle(elided_summary, elided, True)
    assert elided.locator(':scope > p').first.is_visible()
    evidence['original_elided_css_and_toggle'] = elided_style
    # Leave deliberate state different from the stored fixture before navigation.
    pointer_toggle(summary, closed, True)
    evidence['before_navigation'] = states(article)
    assert article.locator('.cooked script, .cooked iframe').count() == 0
    assert article.locator('.cooked').evaluate('node => [...node.querySelectorAll("*")].every(n => [...n.attributes].every(a => !a.name.startsWith("on")))')
    evidence['no_executable_sanitizer_nodes_or_handlers'] = True
    evidence['rendered_cooked_html'] = article.locator('.cooked').inner_html()
    evidence['compiled_fixture_cooked_sha256'] = hashlib.sha256(fixture.encode()).hexdigest()
    return original


def run(prefix, profiler, browser, fixture):
    checkpoint()
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(('127.0.0.1', PORT))
    origin = f'http://127.0.0.1:{PORT}'
    base = origin + prefix
    label = f"profile{int(profiler)}-{'prefix' if prefix else 'root'}"
    env = dict(os.environ, PORT=str(PORT), MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=origin,
               MINIMAL_PROFILER=str(int(profiler)),
               DATABASE_URL=os.environ['DSPINEL_PG_URL'] + '/discourse_development',
               REDIS_URL='redis://127.0.0.1:6399/0')
    with (OUT / f'{label}-server.log').open('w') as log:
        child = subprocess.Popen(['build/bin/discourse'], env=env, stdout=log, stderr=log)
        try:
            for _ in range(100):
                checkpoint()
                assert child.poll() is None, 'owned native ELF exited'
                try:
                    fetch(base + '/srv/status')
                    break
                except OSError:
                    time.sleep(.1)
            else:
                raise AssertionError('native readiness timeout')
            assert Path(f'/proc/{child.pid}/exe').resolve() == Path('build/bin/discourse').resolve()
            with urlopen(base + '/assets/native/css/discourse-details.css', timeout=10) as response:
                assert response.read() == Path('build/assets/details-core/details.css').read_bytes(), 'native CSS is not original compiler output'
            private_paths = ('/assets/details-core/manifest.json', '/assets/native/manifest.json',
                             '/assets/native/css/discourse-details.css.map', '/reference/details-sources/manifest.json',
                             '/assets/details-core/../native/manifest.json')
            for path in private_paths:
                try:
                    response = urlopen(base + path, timeout=10)
                except HTTPError as error:
                    response = error
                with response:
                    assert response.status == 404, (path, response.status)
            topics = fetch(base + '/latest.json')['topic_list']['topics']
            assert len(topics) >= 2
            topic, other = topics[:2]
            api_path = f"/t/{topic['id']}.json"
            with urlopen(base + api_path, timeout=10) as response:
                live_bytes = response.read()
                if profiler:
                    assert 'X-MiniProfiler-Ids' in response.headers
                    assert live_bytes == LIVE_BYTES[(prefix, topic['id'])], 'profiler changed actual topic bytes'
                else:
                    assert 'X-MiniProfiler-Ids' not in response.headers
                    LIVE_BYTES[(prefix, topic['id'])] = live_bytes
            live = json.loads(live_bytes)
            live_post = live['post_stream']['posts'][0]
            inventory = json.loads((OUT / 'live-inventory.json').read_text())
            source_cooked = {row['post_id']: row['sha256'] for row in inventory['counts']['visible_source_cooked']}
            if not prefix:
                assert live_post['id'] in source_cooked, 'must compare real source stored getter independently'
                for post in live['post_stream']['posts']:
                    if not post['hidden']:
                        assert hashlib.sha256(post['cooked'].encode()).hexdigest() == source_cooked[post['id']]
            for viewport, width, height, mobile in [('desktop', 1440, 1000, False), ('phone', 390, 844, True)]:
                for positive in (False, True):
                    checkpoint()
                    kind = 'positive-source-native-fixture-cooked-transport' if positive else 'live-native-read-only-db'
                    stem = f'{label}-{viewport}-{kind}'
                    evidence = {'case': stem, 'evidence_kind': kind, 'positive_live_e2e_claim': False,
                                'prefix': prefix, 'profiler': profiler, 'viewport': viewport, 'native_pid': child.pid,
                                'real_topic_id': topic['id'], 'real_post_id': live_post['id'],
                                'actual_native_topic_sha256': hashlib.sha256(live_bytes).hexdigest(),
                                'private_source_evidence_map_paths_404': list(private_paths),
                                'console': [], 'pageerrors': [], 'failed': [], 'responses': [], 'fixture_requests': []}
                    REPORTS.append(evidence)
                    context = browser.new_context(viewport={'width': width, 'height': height}, is_mobile=mobile,
                                                  has_touch=mobile, device_scale_factor=1)
                    page = context.new_page()
                    page.on('pageerror', lambda error: evidence['pageerrors'].append(str(error)))
                    page.on('console', lambda message: evidence['console'].append({'type': message.type, 'text': message.text}))
                    page.on('requestfailed', lambda request: evidence['failed'].append({'url': request.url, 'failure': request.failure}))
                    page.on('response', lambda response: evidence['responses'].append({'url': response.url, 'status': response.status}))
                    try:
                        def transport(route):
                            if positive and urlsplit(route.request.url).path == prefix + api_path:
                                response = route.fetch()
                                assert response.status == 200
                                body = response.json()
                                assert body == live, 'fixture transport must start with actual native topic data'
                                post = body['post_stream']['posts'][0]
                                assert post['id'] == live_post['id']
                                post['cooked'] = fixture
                                evidence['fixture_requests'].append({'url': route.request.url, 'only_changed_field': 'post_stream.posts[0].cooked',
                                                                    'compiled_cooked_sha256': hashlib.sha256(fixture.encode()).hexdigest()})
                                route.fulfill(response=response, json=body)
                            else:
                                route.continue_()
                        context.route('**/*', transport)
                        page.goto(base + '/latest', wait_until='commit', timeout=10000)
                        page.locator('.topic-list-item').first.wait_for(state='visible', timeout=30000)
                        assert page.locator('.topic-list-item').count() == len(topics)
                        if profiler:
                            page.wait_for_function('window.MiniProfiler && window.MiniProfiler.patchesApplied', timeout=15000)
                        settings = json.loads(json.loads(page.locator('#data-preloaded').text_content())['siteSettings'])
                        assert settings['details_enabled'] is True, 'current live reader evidence expects actual default enabled; never mutate setting'
                        evidence['live_details_enabled'] = settings['details_enabled']
                        page.locator(f".topic-list-item[data-topic-id='{topic['id']}'] a.title").click()
                        article = page.locator(f".topic-post article[data-post-id='{live_post['id']}']")
                        article.locator('.cooked').wait_for(state='visible', timeout=30000)
                        page.wait_for_timeout(150)
                        assert article.locator('.discourse-reactions-counter').count() == 0
                        evidence['preserved_live_reactions_metadata'] = {key: live_post[key] for key in ('reactions', 'reaction_users_count', 'current_user_reaction', 'current_user_used_main_reaction')}
                        css = page.locator(f'link[rel="stylesheet"][href="{prefix}/assets/native/css/discourse-details.css"]')
                        assert css.count() == 1
                        assert any(row['url'] == base + '/assets/native/css/discourse-details.css' for row in evidence['responses'])
                        if positive:
                            assert evidence['fixture_requests'], 'positive data must arrive on actual topic XHR, not DOM injection'
                            initial = exercise(page, article, fixture, evidence)
                            page.screenshot(path=str(OUT / f'{stem}-open.png'), full_page=True)
                        else:
                            assert not evidence['fixture_requests']
                            count = article.locator('.cooked details').count()
                            if inventory['details_posts'] == 0:
                                assert count == 0
                            evidence['live_details_count_in_post'] = count
                            evidence['live_stored_cooked_sha256'] = hashlib.sha256(live_post['cooked'].encode()).hexdigest()
                            if profiler:
                                result = page.locator('.profiler-result').filter(has=page.locator(f'.profiler-name[title="{api_path}"]')).last
                                result.wait_for(state='attached', timeout=15000)
                                result.locator('.profiler-button').click()
                                result.locator('.profiler-popup').wait_for(state='visible')
                                result.locator('.profiler-queries-show').first.click()
                                result.locator('.profiler-queries').wait_for(state='visible')
                                sql = result.locator('.query pre.prettyprint code').all_inner_texts()
                                assert any('FROM posts' in text for text in sql), sql
                                assert any('discourse_reactions_reactions' in text for text in sql), sql
                                assert not any('Closed summary' in text for text in sql)
                                evidence['actual_redacted_native_sql'] = sql
                                # Original SQL drill-down is a separate lightbox;
                                # dismiss it through its backdrop before the badge.
                                page.mouse.click(width - 5, height - 5)
                                page.wait_for_function("!document.querySelector('.profiler-queries-bg')", timeout=5000)
                                result.locator('.profiler-button').click()
                                result.locator('.profiler-popup').wait_for(state='hidden', timeout=5000)
                        # Actual links, no synthetic DOM removal or renderer replacement.
                        page.locator('.d-header .title a').click()
                        page.locator('.topic-list-item').first.wait_for(state='visible', timeout=15000)
                        assert page.locator('.topic-post .cooked details').count() == 0
                        page.locator(f".topic-list-item[data-topic-id='{other['id']}'] a.title").click()
                        other_post = fetch(base + f"/t/{other['id']}.json")['post_stream']['posts'][0]
                        page.locator(f"article[data-post-id='{other_post['id']}'] .cooked").wait_for(state='visible', timeout=15000)
                        assert page.locator('details[id^="post-cooked-html__details-"]').count() == 0
                        page.locator('.d-header .title a').click()
                        page.locator('.topic-list-item').first.wait_for(state='visible', timeout=15000)
                        page.locator(f".topic-list-item[data-topic-id='{topic['id']}'] a.title").click()
                        article = page.locator(f".topic-post article[data-post-id='{live_post['id']}']")
                        article.locator('.cooked').wait_for(state='visible', timeout=15000)
                        if positive:
                            assert states(article) == initial, ('per-post source decorator state must not leak after component destruction', states(article), initial)
                            evidence['after_navigation'] = states(article)
                        evidence['route_away_other_back_no_stale_state'] = True
                        page.wait_for_timeout(200)
                        clean(evidence, base)
                    except Exception as error:
                        evidence['error'] = {'type': type(error).__name__, 'message': str(error)}
                        raise
                    finally:
                        page.screenshot(path=str(OUT / f'{stem}.png'), full_page=True)
                        (OUT / f'{stem}.html').write_text(page.content())
                        context.close()
                    print('Details browser passed: ' + stem, flush=True)
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


if __name__ == '__main__':
    # Parent driver has freshly cooked with original source and independently
    # compiled native topic CTE output; never consume hand-authored HTML snapshots.
    fixtures = json.loads((OUT / 'native-fixtures.json').read_text())
    fixture = fixtures['browser_cooked']
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path='/usr/bin/chromium', headless=True,
                                                args=['--no-sandbox', '--disable-dev-shm-usage'])
            try:
                for profiler in (False, True):
                    for prefix in ('', PREFIX):
                        run(prefix, profiler, browser, fixture)
            finally:
                browser.close()
    finally:
        (OUT / 'browser-report.json').write_text(json.dumps({'scope': __doc__, 'cases': REPORTS}, indent=2) + '\n')

#!/usr/bin/env python3
"""Actual shipped reactions UI: live-native empty data vs labeled fixture transport.

The positive UI case intercepts ONLY topic metadata and users-list transport with
fresh compiled, source-verified CTE fixture output. It is deliberately NOT a
positive live native end-to-end claim. All HTML, modules, styles, avatars and the
Ember menu/UsersPopup lifecycle are served by the owned native ELF.
"""
import json
import os
from pathlib import Path
import signal
import socket
import subprocess
import time
from urllib.parse import parse_qs, urlsplit
from urllib.request import urlopen
from playwright.sync_api import sync_playwright

PORT = int(os.environ.get('MINIMAL_TEST_PORT', '3529'))
assert PORT in (3528, 3529)
PREFIX = '/node/jarvis/widgets/discourse-spinel-app'
OUT = Path('build/reaction-browser')
OUT.mkdir(parents=True, exist_ok=True)
REPORTS = []
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


def assert_clean(evidence, base):
    assert not evidence['pageerrors'], evidence
    assert not evidence['failed'], evidence
    assert not [row for row in evidence['console'] if row['type'] == 'error'], evidence
    assert not [row for row in evidence['responses'] if row['status'] >= 400], evidence
    assert all(row['url'].startswith(base + '/') for row in evidence['responses']), evidence


def scroll_until(page, count, evidence):
    """Drive the original UsersPopup/DLoadMore intersection observer, no API call."""
    popup = page.locator('.users-popup')
    for _ in range(30):
        checkpoint()
        rendered = popup.locator('.users-popup__item:not(.users-popup__skeleton-item)').count()
        if rendered >= count:
            return
        # Desktop scrolls users-popup__body; the original phone modal instead
        # scrolls its d-modal__body ancestor. Scroll the real DLoadMore sentinel
        # into view so Chromium drives the correct original scroll container.
        popup.locator('.load-more-sentinel').scroll_into_view_if_needed(timeout=2000)
        page.wait_for_timeout(150)
    raise AssertionError(('original UsersPopup pagination did not reach count', count, rendered, evidence))


def run(prefix, browser, fixture):
    checkpoint()
    with socket.socket() as probe:
        probe.setsockopt(socket.SOL_SOCKET, socket.SO_REUSEADDR, 1)
        probe.bind(('127.0.0.1', PORT))
    origin = f'http://127.0.0.1:{PORT}'
    base = origin + prefix
    label = 'prefix' if prefix else 'root'
    env = dict(os.environ, PORT=str(PORT), MINIMAL_BASE_URI=prefix, MINIMAL_ORIGIN=origin,
               MINIMAL_PROFILER='1', DATABASE_URL=os.environ['DSPINEL_PG_URL'] + '/discourse_development',
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
                raise AssertionError('owned native readiness timeout')
            assert Path(f'/proc/{child.pid}/exe').resolve() == Path('build/bin/discourse').resolve()
            topic = fetch(base + '/latest.json')['topic_list']['topics'][0]
            path = f"/t/{topic['slug']}/{topic['id']}"
            api = fetch(base + path + '.json')
            post = api['post_stream']['posts'][0]
            assert post['reactions'] == [] and post['reaction_users_count'] == 0, 'live empty-data evidence must be genuinely empty'
            assert post['current_user_reaction'] is None
            for viewport, width, height, mobile in [('desktop', 1440, 1000, False), ('phone', 390, 844, True)]:
                for positive in (False, True):
                    checkpoint()
                    kind = 'positive-source-fixture-mocked-transport' if positive else 'live-native-real-db-empty-state'
                    stem = f'{label}-{viewport}-{kind}'
                    evidence = {'case': stem, 'evidence_kind': kind, 'positive_live_e2e_claim': False,
                                'prefix': prefix, 'viewport': viewport, 'native_pid': child.pid,
                                'real_topic_id': topic['id'], 'real_post_id': post['id'],
                                'console': [], 'pageerrors': [], 'failed': [], 'responses': [],
                                'requests': [], 'fixture_requests': []}
                    REPORTS.append(evidence)
                    context = browser.new_context(viewport={'width': width, 'height': height},
                                                  is_mobile=mobile, has_touch=mobile, device_scale_factor=1)
                    page = context.new_page()
                    page.on('pageerror', lambda error: evidence['pageerrors'].append(str(error)))
                    page.on('console', lambda message: evidence['console'].append({'type': message.type, 'text': message.text}))
                    page.on('requestfailed', lambda request: evidence['failed'].append({'url': request.url, 'failure': request.failure}))
                    page.on('response', lambda response: evidence['responses'].append({'url': response.url, 'status': response.status}))
                    page.on('request', lambda request: evidence['requests'].append({'url': request.url, 'method': request.method}))
                    try:
                        def transport(route):
                            url = route.request.url
                            if not url.startswith(base + '/'):
                                evidence['failed'].append({'url': url, 'failure': 'outside owned prefix'})
                                route.abort()
                                return
                            parsed = urlsplit(url)
                            local = parsed.path.removeprefix(prefix)
                            if positive and local in (path + '.json', f"/t/{topic['id']}.json"):
                                body = json.loads(json.dumps(api))
                                body['post_stream']['posts'][0].update(fixture['metadata'])
                                evidence['fixture_requests'].append({'url': url, 'kind': 'topic-metadata-only', 'compiled_source_fixture': True})
                                route.fulfill(status=200, content_type='application/json; charset=utf-8', body=json.dumps(body))
                                return
                            if positive and local == f"/discourse-reactions/posts/{post['id']}/reactions-users-list.json":
                                args = parse_qs(parsed.query)
                                request_page = int(args.get('page', ['0'])[0])
                                limit = int(args.get('limit', ['30'])[0])
                                reaction = args.get('reaction_value', [''])[0]
                                matches = [row for row in fixture['endpoints'] if row['page'] == request_page and row['limit'] == limit and row['reaction_value'] == reaction]
                                assert len(matches) == 1, (url, fixture['endpoints'])
                                row = matches[0]
                                evidence['fixture_requests'].append({'url': url, 'kind': 'users-list', 'compiled_fixture_path': row['path'], 'page': request_page, 'limit': limit, 'reaction_value': reaction, 'users': len(row['body']['users']), 'total_rows': row['body']['total_rows']})
                                route.fulfill(status=200, content_type='application/json; charset=utf-8', body=json.dumps(row['body']))
                                return
                            route.continue_()
                        context.route('**/*', transport)
                        # Source-native latest link -> real topic XHR. The positive
                        # case replaces data transport, never components or HTML.
                        page.goto(base + '/latest', wait_until='commit', timeout=10000)
                        page.locator('.topic-list-item').first.wait_for(state='visible', timeout=30000)
                        page.wait_for_function('window.MiniProfiler && window.MiniProfiler.patchesApplied', timeout=15000)
                        page.locator(f".topic-list-item[data-topic-id='{topic['id']}'] a.title").click()
                        article = page.locator(f".topic-post article[data-post-id='{post['id']}']")
                        article.locator('.cooked').wait_for(state='visible', timeout=30000)
                        page.wait_for_timeout(400)
                        counter = article.locator('.discourse-reactions-counter')
                        if not positive:
                            assert counter.count() == 0, 'phantom reaction counter on empty live DB'
                            assert article.locator('.reactions-counter').count() == 0
                            assert page.locator('.users-popup').count() == 0
                            assert not [row for row in evidence['requests'] if '/reactions-users' in row['url']]
                            evidence['empty_state'] = {'reactions': post['reactions'], 'reaction_users_count': post['reaction_users_count'], 'counter_count': 0, 'users_menu_count': 0}
                            # Actual redacted native profile must expose metadata
                            # SQL, not fabricated timings from the fixture UI path.
                            profiles = [row for row in evidence['responses'] if urlsplit(row['url']).path == prefix + f"/t/{topic['id']}.json"]
                            assert profiles, 'actual core numeric topic XHR must be observed'
                            profile_name = f"/t/{topic['id']}.json"
                            result = page.locator('.profiler-result').filter(has=page.locator(f'.profiler-name[title="{profile_name}"]')).last
                            result.wait_for(state='attached', timeout=15000)
                            result.locator('.profiler-button').click()
                            popup = result.locator('.profiler-popup')
                            popup.wait_for(state='visible')
                            popup.locator('.profiler-queries-show').first.click()
                            result.locator('.profiler-queries').wait_for(state='visible')
                            sql = result.locator('.query pre.prettyprint code').all_inner_texts()
                            assert any('discourse_reactions_reactions' in text for text in sql), sql
                            assert any('discourse_reactions_reaction_users' in text for text in sql), sql
                            assert any('post_actions' in text for text in sql), sql
                            evidence['redacted_native_metadata_sql'] = sql
                        else:
                            counter.wait_for(state='visible', timeout=10000)
                            preloaded = json.loads(page.locator('#data-preloaded').text_content())
                            prefer_username = json.loads(preloaded['siteSettings'])['prioritize_username_in_ux']
                            evidence['prioritize_username_in_ux'] = prefer_username
                            def expected_names(reaction):
                                rows = sorted([row for row in fixture['endpoints'] if row['reaction_value'] == reaction], key=lambda row: row['page'])
                                return [user['username'] if prefer_username else (user.get('name') or user['username']) for row in rows for user in row['body']['users']]
                            assert counter.count() == 1
                            assert counter.locator('.reactions-counter').inner_text().strip() == str(fixture['metadata']['reaction_users_count'])
                            assert counter.get_attribute('aria-haspopup') == 'dialog'
                            counter.click()
                            popup = page.locator('.users-popup')
                            popup.wait_for(state='visible')
                            scroll_until(page, 30, evidence)
                            evidence['counter_dom'] = counter.evaluate('el => el.outerHTML')
                            assert counter.get_attribute('aria-expanded') == 'true'
                            filters = popup.locator('[data-reaction-filter]').evaluate_all('nodes => nodes.map(n => ({id:n.dataset.reactionFilter,text:n.textContent.trim()}))')
                            assert {row['id'] for row in filters} == {'all'} | {row['id'] for row in fixture['metadata']['reactions']}
                            evidence['filters'] = filters
                            # Choose a source fixture reaction with >30 users so
                            # filtering and its own pagination both hit transport.
                            selected = next(row for row in fixture['metadata']['reactions'] if row['count'] > 30)
                            popup.locator(f"[data-reaction-filter='{selected['id']}']").click()
                            page.wait_for_timeout(200)
                            scroll_until(page, selected['count'], evidence)
                            evidence['filtered_users'] = popup.locator('.users-popup__name').all_inner_texts()
                            assert evidence['filtered_users'] == expected_names(selected['id'])
                            popup.locator("[data-reaction-filter='all']").click()
                            page.wait_for_timeout(200)
                            scroll_until(page, fixture['metadata']['reaction_users_count'], evidence)
                            evidence['all_users'] = popup.locator('.users-popup__name').all_inner_texts()
                            assert evidence['all_users'] == expected_names('')
                            assert len(evidence['all_users']) == fixture['metadata']['reaction_users_count']
                            assert len(set(evidence['all_users'])) == len(evidence['all_users'])
                            assert any(row.get('page') == 1 and row.get('reaction_value') == selected['id'] for row in evidence['fixture_requests'])
                            assert any(row.get('page') == 2 and row.get('reaction_value') == '' for row in evidence['fixture_requests'])
                            evidence['menu_dom'] = popup.evaluate('el => el.outerHTML')
                            page.screenshot(path=str(OUT / f'{stem}-open.png'), full_page=True)
                            (OUT / f'{stem}-open.html').write_text(page.content())
                            # Real route transition, not removing DOM from tests:
                            # original menu constructor/willDestroy subscribe/off.
                            evidence['navigation_trigger'] = 'actual header home anchor click; programmatic event also exercises route cleanup beneath mobile modal'
                            page.locator('.d-header .title a').evaluate('element => element.click()')
                            page.locator('.topic-list-item').first.wait_for(state='visible', timeout=15000)
                            page.wait_for_function("!document.querySelector('.users-popup')", timeout=5000)
                            evidence['route_cleanup'] = {'url': page.url, 'users_popup_count': page.locator('.users-popup').count()}
                            assert page.url in (base + '/', base + '/latest'), page.url
                        page.wait_for_timeout(200)
                        assert_clean(evidence, base)
                    except Exception as error:
                        evidence['error'] = {'type': type(error).__name__, 'message': str(error)}
                        raise
                    finally:
                        page.screenshot(path=str(OUT / f'{stem}.png'), full_page=True)
                        (OUT / f'{stem}.html').write_text(page.content())
                        context.close()
                    print(f'Reactions browser passed: {stem}', flush=True)
        finally:
            child.terminate()
            try:
                child.wait(timeout=5)
            except subprocess.TimeoutExpired:
                child.kill()
                child.wait()


if __name__ == '__main__':
    fixture_doc = json.loads(Path('build/reaction-browser-fixtures-native.json').read_text())
    assert fixture_doc['synthetic'] and fixture_doc['read_only']
    try:
        with sync_playwright() as playwright:
            browser = playwright.chromium.launch(executable_path='/usr/bin/chromium', headless=True, args=['--no-sandbox', '--disable-dev-shm-usage'])
            try:
                for prefix in ('', PREFIX):
                    run(prefix, browser, fixture_doc['browser'])
            finally:
                browser.close()
    finally:
        (OUT / 'browser-report.json').write_text(json.dumps({'scope': __doc__, 'cases': REPORTS}, indent=2) + '\n')

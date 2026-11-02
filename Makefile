.PHONY: build smoke frontend-assets browser-smoke topic-browser-smoke profiler-test boot-test plugin-test reaction-summary-test reaction-browser-test details-test
frontend-assets:
	python3 frontend/stage-reactions.py
	python3 frontend/stage-details.py
	python3 frontend/stage-assets.py --reuse
	python3 tools/stage-media.py
build: frontend-assets
	python3 tools/build.py
smoke: build
	bash test/smoke.sh
browser-smoke: build
	python3 test/browser_cleanup.py
	python3 test/browser_smoke.py --root

topic-browser-smoke: build
	python3 test/topic_browser_test.py
	python3 test/browser_cleanup.py --topic
	python3 test/topic_browser_smoke.py
# Source ../harness/env.sh before invoking. Every server is owned/ephemeral3528/3529.
boot-test: build
	ruby frontend/test_native_document.rb
	python3 test/boot_failure_browser.py

plugin-test: build
	python3 test/plugin_test.py

reaction-summary-test: build
	python3 test/reaction_summary_test.py

reaction-browser-test: build
	python3 test/reaction_browser_test.py

details-test: build
	python3 test/details_test.py

profiler-test: build
	DATABASE_URL="$$DSPINEL_PG_URL/discourse_development" spin test test/profiler_pg.rb
	python3 test/profiler_http.py
	python3 test/profiler_browser.py

.PHONY: build smoke frontend-assets browser-smoke topic-browser-smoke
frontend-assets:
	python3 frontend/stage-assets.py
	python3 tools/stage-media.py
build: frontend-assets
	python3 tools/build.py
smoke: build
	bash test/smoke.sh
browser-smoke: build
	python3 test/browser_cleanup.py
	python3 test/browser_smoke.py --root

topic-browser-smoke: build
	python3 test/browser_cleanup.py --topic
	python3 test/topic_browser_smoke.py

.PHONY: build smoke
build:
	python3 tools/build.py
smoke: build
	bash test/smoke.sh

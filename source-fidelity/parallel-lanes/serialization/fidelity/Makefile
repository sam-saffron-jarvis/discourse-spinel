.PHONY: verify verify-topic-query verify-settings-pure verify-plugin-pure verify-original-latest-input test-original-latest-input verify-original-responder-dispatch
verify:
	python3 tools/verify.py

# Intentionally nonzero until the original native security closure is proven.
verify-topic-query:
	python3 tools/verify_topic_query.py

test-original-latest-input:
	python3 -m unittest tools/test_original_latest_input.py -v

verify-original-responder-dispatch:
	python3 tools/verify_original_responder_dispatch.py --fidelity "$(CURDIR)" --roundhouse "$(ROUNDHOUSE_BIN)" --output "$(OUTPUT_DIR)"

verify-original-latest-input:
	python3 tools/original_latest_input.py --fidelity "$(CURDIR)" --original-repo "$(ORIGINAL_DISCOURSE_ROOT)" --roundhouse "$(ROUNDHOUSE_BIN)" --output "$(OUTPUT_DIR)"

# Pure dependency proof only. Never substitutes for either acceptance target.
verify-settings-pure:
	python3 tools/verify_settings_pure.py

# Actual unconfigured plugin predicate + original in-memory modifier dispatch.
verify-plugin-pure:
	python3 tools/verify_plugin_pure.py

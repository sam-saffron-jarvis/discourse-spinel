.PHONY: verify verify-topic-query verify-settings-pure verify-plugin-pure
verify:
	python3 tools/verify.py

# Intentionally nonzero until the original native security closure is proven.
verify-topic-query:
	python3 tools/verify_topic_query.py

# Pure dependency proof only. Never substitutes for either acceptance target.
verify-settings-pure:
	python3 tools/verify_settings_pure.py

# Actual unconfigured plugin predicate + original in-memory modifier dispatch.
verify-plugin-pure:
	python3 tools/verify_plugin_pure.py

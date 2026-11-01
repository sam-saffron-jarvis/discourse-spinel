# Minimal native implementation path

1. Compile a tiny Spinel TCP listener and read-only PostgreSQL query immediately, using installed native socket support and the existing spinel-pg driver when available.
2. Extract anonymous `TopicQuery#latest` visibility/order and topic-list serializers incrementally. Keep query/serialization adaptations labelled; verify against Rails on the seeded DB without writes.
3. Integrate actual Discourse frontend document/assets only after the JSON contract passes. Never serve recorded oracle responses.
4. `make build` yields native `build/bin/discourse`; `make smoke` owns port 3498 and cleans it up, compares real rows with the Rails reference.

Parallel helpers (no commits): reference owns `reference/`; frontend owns `frontend/`. No whole-app compilation or changes to compiler repositories are planned. Unsupported authenticated/plugin/frontend scope goes in `GAPS.md`.

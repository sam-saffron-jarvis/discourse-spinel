# Discourse on Spinel — bottom-up `/latest`

Initial goal: the actual Discourse topic list in a browser, followed by clicking a topic page. This is a new, local-only extraction repo, NOT the previous 33MB generated tree and not a generic blog demo.

Reference: `../discourse`, original pin `96ce8d44401a8a568ecc71561c26dca8ec6bfeb8`. Compiler work preserved in `../spinel`; previous whole-app/route-shaken efforts parked, not discarded.

## Source and correctness contract
- Start tiny. Bring across actual Discourse code strategically, method-by-method where necessary. Keep `SOURCE_MANIFEST.json` recording original path/SHA, selected definitions and adaptations. Preserve GPL/license notices for copied code.
- Do not run whole-app roundhouse or import every model/concern/gem through a conservative closure. Use existing small Spinel/Ruby HTTP/PG facilities where they help, not 318 models to render a list.
- Runtime adapters must be labelled; copied code, behavior-preserving adaptations and unsupported features must be distinguishable. No hardcoded oracle responses, Rails HTTP proxy masquerading as compiled behavior, or cached fixture responses served as dynamic data.
- Shared *task-owned* PostgreSQL `127.0.0.1:5499/discourse_development`, Valkey `:6399`, existing34 regular topics/115 posts (20/100 seeded). No DDL, reset, seed changes or changes to unrelated services.
- Real ordering/visibility/category/user/serializer behavior checked against Rails. Changes to data must change responses. Never leak private/deleted topics just to make a list nonempty.
- Actual Discourse frontend/assets and bootstrap are the browser goal. A bespoke HTML table is a diagnostic only, not completion. A native health200 is an intermediate result only.
- All core plugins remain the final scope, but each needs a support ledger. Source being copied/discovered does not mean runtime hooks work.

## Parallel ownership
Sol-high owns backend/runtime/integration and commits. Up to2 Luna-high helpers own disjoint `reference/` (Rails comparison contract and cases) and `frontend/` (browser bootstrap/assets research and files). Helpers do not change backend or commit. No third implementation lane; do not optimize the parked whole-slice compiler while this minimal build can progress.

## Task hygiene
See ../docs/PROCESS.md for budgets and supervision. Each source change gets focused tests. Expose `make build` and `make smoke` as deterministic local interfaces; compiled backend listens loopback3499. No public push/PR. Existing widget proxy will expose the app after real local smoke. Leave the live app running after accepted deployment so Sam can click it.

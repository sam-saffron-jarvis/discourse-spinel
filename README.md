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

## Ticket 004 checkpoint: native JSON works; browser is not ready

```sh
# From the run root; uses the installed Spinel and task-owned services only.
source harness/env.sh
make -C minimal build
make -C minimal smoke
```

`build` emits a real ELF at `minimal/build/bin/discourse`, with compiler load graph,
input-byte counts, wall time and peak single-child RSS in `minimal/build/compile.json`.
The PG driver is vendored unchanged and builds without a package fetch. The backend
never launches Ruby, Rails or an HTTP proxy. Its only runtime source-data file is
`data/emoji-unicode.json`, generated from packaged emoji metadata, not oracle output.

`smoke` runs native SELECT-only security/pagination/serializer tests, captures a fresh
Rails contract synchronously with PostgreSQL default/read-only transactions enabled,
then starts its **own** native listener on 3498. It compares every JSON key/value and
array order for two pages, tests HTTP boundaries, and kills/waits its child via trap.
No Rails HTTP process is used. No fixtures/DDL/shared database writes occur. The
current seed produces 20 first-page topics and an empty second page with exact Rails
JSON equality. Evidence/captures are ignored under `build/`, never runtime inputs.

Actual core Ember JS can be reproduced separately (see `frontend/INTEGRATION.md`):

```sh
source harness/env.sh
minimal/frontend/build-ember-assets.sh
```

The wrapper refuses to overwrite an existing output; deliberately remove/relocate
only its known generated `minimal/build/assets/discourse/` output before rebuilding.
This does **not** produce a complete HTML page or CSS/plugin/theme installation.
Normal `/latest` returns **501**. `/latest.json` is not a substitute browser success.
See `GAPS.md`, `PLUGIN_SUPPORT.json`, `SOURCE_MANIFEST.json`, and `NOTICE.md`.

## Coordinator launch / existing widget handoff

After Jarvis accepts the native JSON checkpoint, the foreground command for the
existing task app supervisor (not a new service) is:

```sh
source harness/env.sh
cd minimal
DATABASE_URL="$DSPINEL_PG_URL/discourse_development" \
REDIS_URL='redis://127.0.0.1:6399/0' PORT=3499 ./build/bin/discourse
```

The working directory must be `minimal/` so the source-data file resolves. Keep the
existing widget/app ownership and upstream port convention; the worker has not
changed widgets, registered a service, touched shared `run/app.pid`, or left a
listener running. The current binary can expose API health/JSON through the existing
proxy; do not label it a clickable Discourse topic list while HTML is 501.

**Exact next browser task:** implement the native `Site.json_for(Guardian.new)` and
client-safe `SiteSetting.client_settings_json` preload subset needed by core Ember,
then wire the copied layout's setup metadata/import map, dynamic `topic_list`, actual
core assets and isolated CSS/locale/icon stages at the widget prefix. Observe browser
network/DOM and compare against Rails before claiming `/latest` or starting topic-page
work. Do not substitute saved preloads or raw site-setting rows.
